# frozen_string_literal: true

require 'roda'
require 'slim'
require 'http'
require 'json'
require 'ostruct'

require_relative '../requests/research_interest'
require_relative '../requests/list_paper'
require_relative '../presentation/representers/papers_page_response'
require_relative '../infrastructure/acaradar_api'

# rubocop:disable Metrics/BlockLength
# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/CyclomaticComplexity
# rubocop:disable Naming/MethodParameterName
# rubocop:disable Metrics/MethodLength
# rubocop:disable Metrics/PerceivedComplexity
# rubocop:disable Metrics/ClassLength
module AcaRadar
  # Web App that consumes the AcaRadar API
  class App < Roda
    plugin :caching
    plugin :render, engine: 'slim', views: 'app/presentation/views_slim'
    plugin :assets, css: 'style.css', path: '/assets'
    plugin :static, ['/assets']
    plugin :common_logger, $stderr
    plugin :halt
    plugin :all_verbs
    plugin :flash
    plugin :sessions, secret: ENV.fetch('SESSION_SECRET', 'a_different_secret_for_the_web_app')

    API_BASE = ENV.fetch('ACARADAR_API_URL', 'http://localhost:9292')

    def api_cookie_header
      session[:acaradar_api_cookie].to_s.strip
    end

    def store_api_cookie!(set_cookie_header)
      return if set_cookie_header.nil?

      # HTTP gem may return a single string or an Array
      raw = set_cookie_header.is_a?(Array) ? set_cookie_header : [set_cookie_header]

      # We only need the "name=value" for each cookie (ignore attributes)
      pairs = raw.map { |sc| sc.to_s.split(';', 2).first }.compact

      # Merge with existing cookies (by cookie name)
      existing = {}
      api_cookie_header.split(/;\s*/).each do |pair|
        k, v = pair.split('=', 2)
        existing[k] = v if k && v
      end

      pairs.each do |pair|
        k, v = pair.split('=', 2)
        existing[k] = v if k && v
      end

      session[:acaradar_api_cookie] = existing.map { |k, v| "#{k}=#{v}" }.join('; ')
    end

    def api_request(method:, path:, json: nil, query: nil, headers: {})
      url = "#{API_BASE}#{path}"
      url = "#{url}?#{URI.encode_www_form(query)}" if query && !query.empty?

      h = { 'Accept' => 'application/json' }.merge(headers)
      h['Content-Type'] = 'application/json' if json
      h['Cookie'] = api_cookie_header unless api_cookie_header.empty?

      http = HTTP.headers(h)
      resp =
        if json
          http.public_send(method, url, body: JSON.generate(json))
        else
          http.public_send(method, url)
        end

      store_api_cookie!(resp.headers['Set-Cookie'])
      resp
    end


    route do |routing|
      routing.assets
      response['Content-Type'] = 'text/html; charset=utf-8'

      # GET /
      routing.root do
        @api_host = ENV.fetch('API_HOST')
        puts @api_host
        journal_options = AcaRadar::View::JournalOption.new
        watched_papers = Array(session[:watched_papers])
        response.expires 60, public: true
        view 'home', locals: { options: journal_options, watched_papers: watched_papers }
      end

      routing.post 'watch_paper' do
        response['Content-Type'] = 'application/json'
      
        body = request.body.read.to_s
        payload = JSON.parse(body) rescue {}
      
        session[:watched_papers] ||= []
        session[:watched_papers].unshift(payload.slice('origin_id', 'title', 'published', 'summary'))
        session[:watched_papers] = session[:watched_papers].take(20)
      
        { ok: true }.to_json
      end      

      routing.on 'api_proxy' do
        # Proxy: POST /api_proxy/research_interest  -> API POST /api/v1/research_interest
        routing.post 'research_interest' do
          response['Content-Type'] = 'application/json'
      
          body = request.body.read.to_s
          payload =
            begin
              body.empty? ? {} : JSON.parse(body)
            rescue StandardError
              {}
            end
      
          term = payload['term']
      
          resp = api_request(
            method: :post,
            path: '/api/v1/research_interest',
            json: { term: term }
          )
      
          response.status = resp.code
          resp.to_s
        end
      
        # Proxy: GET /api_proxy/papers -> API GET /api/v1/papers (keeps same API session)
        routing.get 'papers' do
          response['Content-Type'] = 'application/json'
      
          # pass through query params (journal1, journal2, page, etc.)
          resp = api_request(
            method: :get,
            path: '/api/v1/papers',
            query: routing.params
          )
      
          response.status = resp.code
          resp.to_s
        end
      end      

      routing.on 'research_interest' do
        routing.post do
          request = Request::EmbedResearchInterest.new(routing.params)

          unless request.valid?
            flash[:error] = 'Research interest cannot be empty.'
            routing.redirect '/'
          end

          result = Service::EmbedResearchInterest.call(request)

          if result.success?
            raw = begin
              JSON.parse(result.message)
            rescue StandardError
              {}
            end
            payload = raw.is_a?(Hash) && raw.key?('data') ? raw['data'] : raw

            session[:research_interest_term] = payload['term'] || request.term
            session[:research_interest_2d]   =
              normalize_vector_2d(payload['vector_2d'] || payload['research_interest_2d'])

            flash[:notice] = 'Research interest has been set!'
          else
            flash[:error] = result.message
          end

          routing.redirect '/'
        end
      end

      # GET /selected_journals
      routing.on 'selected_journals' do
        request = Request::ListPapers.new(routing.params)
        research_interest_term = routing.params['term']
        vector_x = routing.params['vector_x']
        vector_y = routing.params['vector_y']
        research_interest_2d = vector_x && vector_y ? [vector_x.to_f, vector_y.to_f] : nil

        unless request.valid?
          flash[:notice] = 'Please select 2 different journals.'
          routing.redirect '/'
        end

        resp = api_request(
          method: :get,
          path: '/api/v1/papers',
          query: routing.params
        )

        unless resp.status.success?
          raw_err = begin
            JSON.parse(resp.to_s)
          rescue StandardError
            {}
          end
          msg = raw_err['message'] || "API Error (#{resp.code})"
          flash[:error] = msg
          routing.redirect '/'
        end

        raw = begin
          JSON.parse(resp.to_s)
        rescue StandardError
          {}
        end

        
        payload_hash = raw.is_a?(Hash) && raw.key?('data') ? raw['data'] : raw
        payload_json = payload_hash.to_json

        papers_page = Representer::PapersPageResponse.new(OpenStruct.new)
                                                     .from_json(payload_json)

        response.expires 60, public: true
        view 'selected_journals',
             locals: {
               journals: papers_page.journals || [],
               papers: Array(papers_page.papers&.data).map { |p| AcaRadar::View::Paper.new(p) },
               research_interest_term: research_interest_term,
               research_interest_2d: research_interest_2d, # ALWAYS nil or [x,y]
               pagination: papers_page.pagination || {},
               error: nil
             }
      end
    end

    private

    # Normalizes API shapes into either nil or [x, y]
    # Accepts:
    #   {"x"=>0.1,"y"=>-0.2} OR {x:0.1,y:-0.2} OR [0.1,-0.2]
    def normalize_vector_2d(v)
      return nil if v.nil?

      if v.is_a?(Hash)
        x = v['x'] || v[:x]
        y = v['y'] || v[:y]
        return nil if x.nil? || y.nil?

        return [x.to_f, y.to_f]
      end

      if v.is_a?(Array) && v.size >= 2
        x = v[0]
        y = v[1]
        return nil if x.nil? || y.nil?

        return [x.to_f, y.to_f]
      end

      nil
    rescue StandardError
      nil
    end
  end
end
# rubocop:enable Metrics/BlockLength
# rubocop:enable Metrics/AbcSize
# rubocop:enable Metrics/CyclomaticComplexity
# rubocop:enable Naming/MethodParameterName
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/PerceivedComplexity
# rubocop:enable Metrics/ClassLength
