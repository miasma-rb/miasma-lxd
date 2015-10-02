require 'miasma'

module Miasma
  module Models
    class Compute
      # LXD compute API
      class Lxd < Compute

        include Contrib::Lxd::Api

        # State mapping based on status
        SERVER_STATE_MAP = Smash.new(
          'running' => :running,
          'stopped' => :stopped
        )

        # Reload a server model's data
        #
        # @param server [Miasma::Models::Compute::Server]
        # @return [Miasma::Models::Compute::Server]
        def server_reload(server)
          result = request(
            :path => "containers/#{server.id}",
            :expects => [200, 404]
          )
          if(result[:response].code == 200)
            result = result.get(:body, :metadata)
            server.load_data(
              :id => result[:name],
              :name => result[:name],
              :state => SERVER_STATE_MAP.fetch(result.get(:status, :status).downcase, :pending),
              :status => result.fetch(:status, :status, 'unknown').downcase,
              :addresses_private => (result.get(:status, :ips) || []).map{ |ip|
                Server::Address.new(
                  :version => ip[:protocol].downcase.sub('ipv', '').to_i,
                  :address => ip[:address]
                )
              },
              :image_id => 'unknown',
              :flavor_id => result.get(:profiles).first,
              :userdata => result.get(:userdata),
              :custom => Smash.new(
                :ephemeral => result[:ephemeral]
              )
            )
          else
            server.load_data(
              :id => server.id,
              :name => server.name,
              :state => :terminated,
              :status => 'terminated',
              :addresses_private => [],
              :image_id => 'none',
              :flavor_id => 'none'
            )
          end
          server.valid_state
        end

        # Destroy an existing server
        #
        # @param server [Miasma::Models::Compute::Server]
        # @return [TrueClass, FalseClass]
        def server_destroy(server)
          if(server.persisted?)
            if(server.state == :running)
              result = request(
                :path => "containers/#{server.id}/state",
                :method => :put,
                :expects => 202,
                :json => {
                  :action => :stop,
                  :force => true
                }
              )
              wait_for_operation(result.get(:body, :operation))
            end
            request(
              :path => "containers/#{server.id}",
              :method => :delete,
              :expects => 202
            )
            true
          else
            false
          end
        end

        # Save the server (create or update)
        #
        # @param server [Miasma::Models::Compute::Server]
        # @return [Miasma::Models::Compute::Server]
        def server_save(server)
          if(server.persisted?)
          else
            result = request(
              :path => 'containers',
              :method => :post,
              :expects => 202,
              :json => {
                :name => server.name,
                :profiles => [server.flavor_id],
                :ephemeral => server.custom.fetch(:ephemeral, false),
                :source => {
                  :type => :image,
                  :alias => server.image_id
                }
              }
            )
            wait_for_operation(result.get(:body, :operation))
            request(
              :path => "containers/#{server.name}/state",
              :method => :put,
              :expects => 202,
              :json => {
                :action => :start
              }
            )
            wait_for_operation(result.get(:body, :operation))
            server.id = server.name
            server
          end
        end

        # Return all servers
        #
        # @return [Array<Miasma::Models::Compute::Server>]
        def server_all
          result = request(
            :path => 'containers'
          ).get(:body)
          result.fetch(:metadata, []).map do |c_info|
            c_name = c_info.sub("/#{version}/containers/", '')
            Server.new(
              self,
              :id => c_name,
              :name => c_name,
              :image_id => 'unknown',
              :flavor_id => 'unknown',
              :state => :pending,
              :status => 'unknown'
            ).valid_state
          end
        end

        protected

        # Wait for a remote operation to complete
        #
        # @param op_uuid [String]
        # @return [TrueClass]
        def wait_for_operation(op_uuid)
          op_uuid = op_uuid.sub("/#{version}/operations/", '')
          request(
            :path => "operations/#{op_uuid}/wait",
            :params => {
              :status_code => 200,
              :timeout => 20
            }
          )
          true
        end

      end
    end
  end
end
