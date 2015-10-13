require 'miasma'
require 'shellwords'
require 'bogo-websocket'

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

        # @return [Integer]
        DEFAULT_EXEC_TIMEOUT = 30

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
            until(server.state == :running)
              request(
                :path => "containers/#{server.name}/state",
                :method => :put,
                :expects => 202,
                :json => {
                  :action => :start
                }
              )
              wait_for_operation(result.get(:body, :operation), 60)
              server.reload
            end
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
              :name => c_name
            ).valid_state
          end
        end

        # Fetch file from server
        #
        # @param server [Miasma::Models::Compute::Server]
        # @param path [String] remote path
        # @return [IO-ish]
        def server_get_file(server, path)
          request(
            :path => "containers/#{server.id}/files",
            :params => {
              :path => path
            },
            :disable_body_extraction => true
          ).get(:body)
        end

        # Put file on server
        #
        # @param server [Miasma::Models::Compute::Server]
        # @param io [IO-ish]
        # @param remote_path [String]
        # @return [TrueClass]
        def server_put_file(server, io, remote_path, options={})
          request(
            :method => :post,
            :path => "containers/#{server.id}/files",
            :params => {
              :path => remote_path
            },
            :body => io,
            :headers => {
              'Transfer-Encoding' => 'chunked',
              'X-LXD-uid' => options.fetch(:uid, 0),
              'X-LXD-gid' => options.fetch(:gid, 0),
              'X-LXD-mode' => options.fetch(:mode, 0700)
            }
          )
          true
        end

        # Execute command
        #
        # @param server [Miasma::Models::Compute::Server]
        # @param command [String]
        # @param options [Hash]
        # @option options [IO] :stream write command output
        # @option options [Integer] :return_exit_code
        # @option options [Integer] :timeout
        # @return [TrueClass, FalseClass, Integer] command was successful
        def server_execute(server, command, options={})
          result = request(
            :method => :post,
            :path => "containers/#{server.id}/exec",
            :expects => 202,
            :json => Smash.new(
              :command => Shellwords.shellwords(command),
              :interactive => true,
              'wait-for-websocket' => true,
              :environment => options.fetch(:environment, {})
            )
          )
          dest = URI.parse(api_endpoint)
          operation = result.get(:body, :operation).sub("/#{version}/operations/", '')
          ws_common = Smash.new(
            :ssl_key => ssl_key,
            :ssl_certificate => ssl_certificate
          )
          if(options[:stream])
            ws_common[:on_message] = proc{|message|
              options[:stream].write(message)
            }
          end
          websockets = Smash[
            ['control', '0'].map do |fd_id|
              fd_secret = result.get(:body, :metadata, :fds, fd_id)
              [
                fd_id,
                Bogo::Websocket::Client.new(
                  ws_common.merge(
                    :destination => "wss://#{[dest.host, dest.port].compact.join(':')}",
                    :path => "/#{version}/operations/#{operation}/websocket",
                    :params => {
                      :secret => fd_secret
                    }
                  )
                )
              ]
            end
          ]
          wait_for_operation(operation, options.fetch(:timeout, DEFAULT_EXEC_TIMEOUT))
          websockets.map(&:last).map(&:close)
          result = request(
            :path => "operations/#{operation}"
          )
          if(options[:return_exit_code])
            result.get(:body, :metadata, :metadata, :return)
          else
            result.get(:body, :metadata, :metadata, :return) == 0
          end
        end

        protected

        # Wait for a remote operation to complete
        #
        # @param op_uuid [String]
        # @param timeout [Integer]
        # @return [TrueClass]
        def wait_for_operation(op_uuid, timeout=DEFAULT_EXEC_TIMEOUT)
          op_uuid = op_uuid.sub("/#{version}/operations/", '')
          request(
            :path => "operations/#{op_uuid}/wait",
            :params => {
              :status_code => 200,
              :timeout => timeout
            }
          )
          true
        end

      end
    end
  end
end
