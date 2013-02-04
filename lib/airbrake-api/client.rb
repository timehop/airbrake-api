require 'faraday_middleware'
require 'airbrake-api/core_ext/hash'
require 'airbrake-api/middleware/scrub_response'
require 'airbrake-api/middleware/raise_server_error'
require 'airbrake-api/middleware/raise_response_error'

module AirbrakeAPI
  class Client

    PER_PAGE = 30
    PARALLEL_WORKERS = 10

    attr_accessor *AirbrakeAPI::Configuration::VALID_OPTIONS_KEYS

    def initialize(options={})
      attrs = AirbrakeAPI.options.merge(options)
      AirbrakeAPI::Configuration::VALID_OPTIONS_KEYS.each do |key|
        send("#{key}=", attrs[key])
      end
    end

    def url_for(endpoint, *args)
      path = case endpoint.to_s
      when 'deploys' then deploys_path(*args)
      when 'projects' then '/projects'
      when 'errors' then errors_path
      when 'error' then error_path(*args)
      when 'notices' then notices_path(*args)
      when 'notice' then notice_path(*args)
      else raise ArgumentError.new("Unrecognized path: #{path}")
      end

      [account_path, path.split('.').first].join('')
    end

    # deploys

    def deploys(project_id, options = {})
      results = request(:get, deploys_path(project_id), options)
      results.projects.respond_to?(:deploy) ? results.projects.deploy : []
    end

    def deploys_path(project_id)
      "/projects/#{project_id}/deploys.xml"
    end

    # projects
    def projects_path
      '/data_api/v1/projects.xml'
    end

    def projects(options = {})
      results = request(:get, projects_path, options)
      results.projects.project
    end

    # errors

    def unformatted_error_path(error_id)
      "#{path_prefix}/groups/#{error_id}"
    end

    def error_path(error_id)
      "#{unformatted_error_path(error_id)}#{xml_suffix}"
    end

    def errors_path
      "#{path_prefix}/groups#{xml_suffix}"
    end

    def update(error, options = {})
      results = request(:put, unformatted_error_path(error), options)
      results.group
    end

    def error(error_id, options = {})
      results = request(:get, error_path(error_id), options)
      results.group || results.groups || results
    end

    def errors(options = {})
      results = request(:get, errors_path, options)
      results.group || results.groups || (results.result && results.result.groups)
    end

    # notices

    def notice_path(notice_id, error_id)
      "#{path_prefix}/groups/#{error_id}/notices/#{notice_id}#{xml_suffix}"
    end

    def notices_path(error_id)
      "#{path_prefix}/groups/#{error_id}/notices#{xml_suffix}"
    end

    def notice(notice_id, error_id, options = {})
      hash = request(:get, notice_path(notice_id, error_id), options)
      hash.notice || hash
    end

    def notices(error_id, options = {}, &block)
      # a specific page is requested, only return that page
      # if no page is specified, start on page 1
      if options[:page]
        page = options[:page]
        options[:pages] = 1
      else
        page = 1
      end

      notices = []
      page_count = 0
      while !options[:pages] || (page_count + 1) <= options[:pages]
        data = request(:get, notices_path(error_id), :page => page + page_count)

        this_data = data.notices || data.resuilt
        batch = if options[:raw]
          this_data
        else
          # get info like backtraces by doing another api call to notice
          Parallel.map(this_data, :in_threads => PARALLEL_WORKERS) do |notice_stub|
            notice(notice_stub.id, error_id)
          end
        end
        yield batch if block_given?
        batch.each{|n| notices << n }

        break if batch.size < PER_PAGE
        page_count += 1
      end
      notices
    end

    private

    def path_prefix
      should_use_new_api? ? "/api/v1/projects/#{@account_id}" : ""
    end

    def xml_suffix
      should_use_new_api? ? "" : ".xml"
    end

    def account_path
      if should_use_new_api?
        "#{protocol}://collect.airbrake.io"
      else
        "#{protocol}://#{@account}.airbrake.io"
      end
    end

    def protocol
      @secure ? "https" : "http"
    end

    # Perform an HTTP request
    def request(method, path, params = {}, options = {})

      raise AirbrakeError.new('API Token cannot be nil') if @auth_token.nil?
      raise AirbrakeError.new('Account cannot be nil') if @account.nil?

      response = connection(options).run_request(method, nil, nil, nil) do |request|
        case method
        when :delete, :get
          request.url(path, params.merge(:auth_token => @auth_token))
        when :post, :put
          request.url(path, :auth_token => @auth_token)
          request.body = params unless params.empty?
        end
      end
      response.body
    end

    def connection(options={})
      default_options = {
        :headers => {
          :accept => 'application/xml,application/json',
          :user_agent => user_agent,
        },
        :ssl => {:verify => false},
        :url => account_path,
      }
      @connection ||= Faraday.new(default_options.deep_merge(connection_options)) do |builder|
        builder.use Faraday::Request::UrlEncoded
        builder.use AirbrakeAPI::Middleware::RaiseResponseError
        builder.use FaradayMiddleware::Mashify
        builder.use FaradayMiddleware::ParseXml,  :content_type => /\bxml$/
        builder.use FaradayMiddleware::ParseJson, :content_type => /\bjson$/
        builder.use AirbrakeAPI::Middleware::ScrubResponse
        builder.use AirbrakeAPI::Middleware::RaiseServerError

        builder.adapter adapter
      end
    end

    def should_use_new_api?
      @api_version && @api_version >= 3 && @account_id
    end

  end
end
