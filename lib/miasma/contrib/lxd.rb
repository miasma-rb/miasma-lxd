require 'miasma'

module Miasma
  module Contrib
    module Lxd
      # API updates required for LXD communication
      module Api

        # Default API version to require
        DEFAULT_API_VERSION = '1.0'

        # Load required attributes into API class
        #
        # @param klass [Class]
        def self.included(klass)
          klass.class_eval do
            attribute :name, String, :required => true, :default => Socket.gethostname
            attribute :password, String
            attribute :api_endpoint, String, :required => true
            attribute :ssl_certificate, String, :required => true
            attribute :ssl_key, String, :required => true
            attribute :version, Gem::Version, :coerce => lambda{|v| Gem::Version.new(v.to_s)}, :required => true, :default => lambda{ Miasma::Contrib::Lxd::Api::DEFAULT_API_VERSION }
            attribute :image_server, String, :default => 'https://images.linuxcontainers.org:8443'
          end
        end

        # @return [String] versioned endpoint
        def endpoint
          "#{api_endpoint}/#{version}"
        end

        # Clean up endpoint prior to data loading
        #
        # @param args [Hash]
        def custom_setup(args)
          if(args[:api_endpoint].to_s.end_with?('/'))
            args[:api_endpoint] = args[:api_endpoint][0, endpoint.length - 1]
          end
        end

        # Perform request
        #
        # @param connection [HTTP]
        # @param http_method [Symbol]
        # @param request_args [Array]
        # @return [HTTP::Response]
        def make_request(connection, http_method, request_args)
          dest, options = request_args
          options = Smash.new unless options
          options[:ssl_context] = ssl_context
          connection.send(http_method, dest, options)
        end

        # Never retry requests
        #
        # @return [FalseClass]
        def perform_request_retry(*_)
          false
        end

        protected

        # @return [OpenSSL::SSL::SSLContext.new]
        def ssl_context
          memoize(:ssl_context) do
            ctx = OpenSSL::SSL::SSLContext.new
            ctx.cert = OpenSSL::X509::Certificate.new(File.read(ssl_certificate))
            ctx.key = OpenSSL::PKey::RSA.new(File.read(ssl_key))
            ctx
          end
        end

        # Establish connection to endpoint and register client if not
        # already registered
        def connect
          result = request(:endpoint => api_endpoint)[:body]
          unless(result[:metadata].any?{|s| s.end_with?(version.to_s)})
            raise InvalidVersionError
          end
          result = request(:endpoint => api_endpoint, :path => "/#{version}")[:body]
          if(result[:auth] != 'trusted' && password)
            authenticate_connection!
          end
        end

        # Authenticate with the endpoint to create trusted connection
        def authenticate_connection!
          request(
            :method => :post,
            :path => 'certificates',
            :json => {
              :type => :client,
              :name => name,
              :password => password
            }
          )
        end

      end
    end
  end

  Models::Compute.autoload :Lxd, 'miasma/contrib/lxd/compute'
end
