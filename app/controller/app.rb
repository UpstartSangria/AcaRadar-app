# frozen_string_literal: true

require 'roda'
require 'slim'
require 'http'
require 'json'
require 'ostruct'
require 'uri'

require_relative '../requests/research_interest'
require_relative '../requests/list_paper'
require_relative '../presentation/representers/papers_page_response'
require_relative '../infrastructure/acaradar_api'

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

    # -----------------------------
    # Debug helper
    # -----------------------------
    def dbg(msg)
      $stderr.puts("[WEBAPP DEBUG] #{msg}")
    end

    def safe_json_parse(str)
      JSON.parse(str)
    rescue StandardError => e
      dbg("JSON.parse failed: #{e.class} - #{e.message} input=#{str.to_s[0, 200].inspect}")
      {}
    end

    # -----------------------------
    # API cookie bridge
    # -----------------------------
    def api_cookie_header
      session[:acaradar_api_cookie].to_s.strip
    end

    def store_api_cookie!(set_cookie_header)
      if set_cookie_header.nil?
        dbg("store_api_cookie!: no Set-Cookie header present")
        return
      end

      # HTTP gem may return a single string or an Array
      raw = set_cookie_header.is_a?(Array) ? set_cookie_header : [set_cookie_header]

      # to save cookies from exploding
      pairs = raw
        .map { |sc| sc.to_s.split(';', 2).first }
        .compact
        .select { |pair| pair.start_with?('acaradar.session=') }  # only keep the API session


      existing = {}
      api_cookie_header.split(/;\s*/).each do |pair|
        k, v = pair.split('=', 2)
        existing[k] = v if k && v
      end

      pairs.each do |pair|
        k, v = pair.split('=', 2)
        existing[k] = v if k && v
      end

      merged = existing.map { |k, v| "#{k}=#{v}" }.join('; ')
      session[:acaradar_api_cookie] = merged

      dbg("store_api_cookie!: stored cookies=#{merged.inspect}")
    rescue StandardError => e
      dbg("store_api_cookie! ERROR: #{e.class} - #{e.message}")
    end

    def api_request(method:, path:, json: nil, query: nil, headers: {})
      url = "#{API_BASE}#{path}"
      url = "#{url}?#{URI.encode_www_form(query)}" if query && !query.empty?

      h = { 'Accept' => 'application/json' }.merge(headers)
      h['Content-Type'] = 'application/json' if json
      h['Cookie'] = api_cookie_header unless api_cookie_header.empty?

      dbg("api_request: #{method.to_s.upcase} #{url} cookie_present=#{!api_cookie_header.empty?}")

      http = HTTP.headers(h)
      resp =
        if json
          http.public_send(method, url, body: JSON.generate(json))
        else
          http.public_send(method, url)
        end

      # Critical: header key can be 'set-cookie' depending on the HTTP gem version
      set_cookie = resp.headers['Set-Cookie'] || resp.headers['set-cookie']
      dbg("api_request: response code=#{resp.code} set_cookie_present=#{!set_cookie.nil?}")

      store_api_cookie!(set_cookie)
      resp
    rescue StandardError => e
      dbg("api_request ERROR: #{e.class} - #{e.message}")
      raise
    end

    route do |routing|
      routing.assets
      response['Content-Type'] = 'text/html; charset=utf-8'

      # -----------------------------
      # GET /
      # -----------------------------
      routing.root do
        @api_host = ENV.fetch('API_HOST', '')
        dbg("GET / : api_host=#{@api_host.inspect} web_session_cookie_keys=#{(session.to_h.keys rescue []).inspect}")

        journal_options = AcaRadar::View::JournalOption.new

        watched_papers = Array(session[:watched_papers]).map do |h|
          h = h.is_a?(Hash) ? h : {}
          OpenStruct.new(
            origin_id: h['origin_id'],
            pdf_url: h['pdf_url'],
            title: h['title'],
            published: h['published'],
            summary: h['summary']
          )
        end

        # Home can be cached lightly, but it's user/session-ish; keep it private
        response.expires 60, public: false

        watched_papers = Array(session[:watched_papers]).take(3)
        view 'home', locals: { options: journal_options, watched_papers: watched_papers }
      end

      # -----------------------------
      # POST /watch_paper
      # -----------------------------
      routing.post 'watch_paper' do
        response['Content-Type'] = 'application/json'

        body = request.body.read.to_s
        payload = safe_json_parse(body)
        dbg("POST /watch_paper payload_keys=#{payload.keys.inspect}")

        pdf_url   = (payload['pdf_url'] || payload[:pdf_url]).to_s.strip
        title     = (payload['title'] || payload[:title]).to_s.strip
        published = (payload['published'] || payload[:published]).to_s.strip

        if pdf_url.empty?
          response.status = 400
          return { ok: false, error: 'pdf_url missing' }.to_json
        end

        item = { 'pdf_url' => pdf_url, 'title' => title, 'published' => published }

        session[:watched_papers] ||= []
        session[:watched_papers] =
          [item] + session[:watched_papers].reject { |p| (p['pdf_url'] || p[:pdf_url]).to_s == pdf_url }
        session[:watched_papers] = session[:watched_papers].take(3)

        { ok: true }.to_json
      end

      # -----------------------------
      # /api_proxy (keeps API session cookie)
      # -----------------------------
      routing.on 'api_proxy' do
        # Proxy: POST /api_proxy/research_interest -> API POST /api/v1/research_interest
        routing.post 'research_interest' do
          response['Content-Type'] = 'application/json'

          body = request.body.read.to_s
          payload = safe_json_parse(body)

          term = payload['term']
          dbg("api_proxy/research_interest: term=#{term.inspect} BEFORE cookie=#{api_cookie_header.inspect}")

          resp = api_request(
            method: :post,
            path: '/api/v1/research_interest',
            json: { term: term }
          )

          dbg("api_proxy/research_interest: AFTER cookie=#{api_cookie_header.inspect}")

          # Try to log what the API returned about concepts/request_id
          begin
            parsed = safe_json_parse(resp.to_s)
            data = parsed.is_a?(Hash) ? (parsed['data'] || {}) : {}
            dbg("api_proxy/research_interest: api_data_keys=#{data.keys.inspect} request_id=#{data['request_id'].inspect} status=#{data['status'].inspect} concepts_len=#{Array(data['concepts']).length}")
          rescue StandardError
            # safe_json_parse already logs
          end

          response.status = resp.code
          resp.to_s
        end

        # Proxy: GET /api_proxy/papers -> API GET /api/v1/papers
        routing.get 'papers' do
          response['Content-Type'] = 'application/json'
          dbg("api_proxy/papers: params_keys=#{routing.params.keys.sort.inspect} cookie_present=#{!api_cookie_header.empty?}")

          resp = api_request(
            method: :get,
            path: '/api/v1/papers',
            query: routing.params
          )

          response.status = resp.code
          resp.to_s
        end
      end

      # -----------------------------
      # POST /research_interest (legacy non-AJAX)
      # -----------------------------
      routing.on 'research_interest' do
        routing.post do
          request_obj = Request::EmbedResearchInterest.new(routing.params)

          unless request_obj.valid?
            flash[:error] = 'Research interest cannot be empty.'
            routing.redirect '/'
          end

          result = Service::EmbedResearchInterest.call(request_obj)

          if result.success?
            raw = safe_json_parse(result.message)
            payload = raw.is_a?(Hash) && raw.key?('data') ? raw['data'] : raw

            session[:research_interest_term] = payload['term'] || request_obj.term
            session[:research_interest_2d]   = normalize_vector_2d(payload['vector_2d'] || payload['research_interest_2d'])

            flash[:notice] = 'Research interest has been set!'
          else
            flash[:error] = result.message
          end

          routing.redirect '/'
        end
      end

      # -----------------------------
      # GET /selected_journals
      # -----------------------------
      routing.on 'selected_journals' do
        request_obj = Request::ListPapers.new(routing.params)

        research_interest_term = routing.params['term']
        vector_x = routing.params['vector_x']
        vector_y = routing.params['vector_y']
        research_interest_2d = vector_x && vector_y ? [vector_x.to_f, vector_y.to_f] : nil

        ri_job_id = routing.params['request_id'].to_s.strip

        dbg("GET /selected_journals: params_keys=#{routing.params.keys.sort.inspect}")
        dbg("GET /selected_journals: request_id=#{ri_job_id.inspect} cookie_before=#{api_cookie_header.inspect}")

        unless request_obj.valid?
          flash[:notice] = 'Please select 2 different journals.'
          routing.redirect '/'
        end

        # --- Step 1: Poll RI job until completed, to capture concepts + to force API session set ---
        research_interest_concepts = []

        if ri_job_id.empty?
          dbg("GET /selected_journals: NO request_id param -> concepts cannot be fetched (will remain empty)")
        else
          tries = 10
          delay = 0.20

          tries.times do |i|
            ri_resp = api_request(method: :get, path: "/api/v1/research_interest/#{ri_job_id}")

            ri_raw = safe_json_parse(ri_resp.to_s)
            ri_data = ri_raw.is_a?(Hash) && ri_raw.key?('data') ? ri_raw['data'] : ri_raw

            status = ri_data['status'].to_s
            concepts_arr = Array(ri_data['concepts']).map(&:to_s)

            dbg("RI poll #{i + 1}/#{tries}: http=#{ri_resp.code} status=#{status.inspect} concepts_len=#{concepts_arr.length} cookie_now=#{api_cookie_header.inspect}")

            # record latest concepts we saw (if any)
            research_interest_concepts = concepts_arr if concepts_arr.any?

            break if status == 'completed'
            break if status == 'failed'

            sleep(delay)
          end
        end

        dbg("GET /selected_journals: FINAL concepts_len=#{research_interest_concepts.length} concepts_sample=#{research_interest_concepts.first(10).inspect}")

        # --- Step 2: Fetch papers (same cookie) ---
        resp = api_request(
          method: :get,
          path: '/api/v1/papers',
          query: routing.params
        )

        dbg("GET /selected_journals: papers http=#{resp.code} cookie_after_papers=#{api_cookie_header.inspect}")

        unless resp.status.success?
          raw_err = safe_json_parse(resp.to_s)
          msg = raw_err['message'] || "API Error (#{resp.code})"
          flash[:error] = msg
          routing.redirect '/'
        end

        raw = safe_json_parse(resp.to_s)
        payload_hash = raw.is_a?(Hash) && raw.key?('data') ? raw['data'] : raw
        payload_json = payload_hash.to_json

        papers_page =
          Representer::PapersPageResponse.new(OpenStruct.new).from_json(payload_json)

        response.expires 0, public: false

        view 'selected_journals',
             locals: {
               journals: papers_page.journals || [],
               papers: Array(papers_page.papers&.data).map { |p| AcaRadar::View::Paper.new(p) },
               research_interest_term: research_interest_term,
               research_interest_2d: research_interest_2d,
               research_interest_concepts: research_interest_concepts, # <-- now available to slim locals
               pagination: papers_page.pagination || {},
               error: nil
             }
      end
    end

    private

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
