require 'airbrake-api/version'

module AirbrakeAPI
  module Configuration
    VALID_OPTIONS_KEYS = [
      :account,
      :auth_token,
      :secure,
      :connection_options,
      :adapter,
      :user_agent,
      :account_id,
      :api_version]

    attr_accessor *VALID_OPTIONS_KEYS

    DEFAULT_ADAPTER     = :net_http
    DEFAULT_USER_AGENT  = "AirbrakeAPI Ruby Gem #{AirbrakeAPI::VERSION}"
    DEFAULT_CONNECTION_OPTIONS = {}

    def self.extended(base)
      base.reset
    end

    def configure(options={})
      @account     = options[:account] if options.has_key?(:account)
      @auth_token  = options[:auth_token] if options.has_key?(:auth_token)
      @secure      = options[:secure] if options.has_key?(:secure)
      @account_id  = options[:account_id] if options.has_key?(:account_id)
      @api_version = options[:api_version] if options.has_key?(:api_version)
      yield self if block_given?
      self
    end

    def options
      options = {}
      VALID_OPTIONS_KEYS.each{|k| options[k] = send(k)}
      options
    end

    def account_path
      if should_use_new_api?
        "#{protocol}://collect.airbrake.io/api/v1/projects/#{@account_id}"
      else
        "#{protocol}://#{@account}.airbrake.io"
      end
    end

    def protocol
      @secure ? "https" : "http"
    end

    def reset
      @account     = nil
      @auth_token  = nil
      @secure      = false
      @adapter     = DEFAULT_ADAPTER
      @user_agent  = DEFAULT_USER_AGENT
      @connection_options = DEFAULT_CONNECTION_OPTIONS
      @account_id  = nil
      @api_version = nil
    end

    def should_use_new_api?
      @api_version && @api_version >= 3 && @account_id
    end

  end
end
