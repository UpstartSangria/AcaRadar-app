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
    plugin :sessions,
           secret: ENV.fetch('SESSION_SECRET', 'a_different_secret_for_the_web_app')

    route do |routing|
      routing.assets
      response['Content-Type'] = 'text/html; charset=utf-8'

      # GET /
      routing.root do
        @api_host = ENV.fetch('API_HOST')
        puts @api_host
        journal_options = AcaRadar::View::JournalOption.new
        watched_papers = []
        response.expires 60, public: true
        view 'home', locals: { options: journal_options, watched_papers: watched_papers }
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

        result = Service::ListPapers.call(request)

        if result.failure?
          flash[:error] = "API Error: #{result.message}"
          routing.redirect '/'
        end

        raw = begin
          JSON.parse(result.message)
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
