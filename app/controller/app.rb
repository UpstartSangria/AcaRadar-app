# frozen_string_literal: true

require 'roda'
require 'slim'
require 'http'
require 'json'

require_relative '../requests/research_interest'
require_relative '../requests/list_paper'
require_relative '../presentation/representers/papers_page_response'
require_relative '../infrastructure/acaradar_api'

# rubocop:disable Metrics/BlockLength
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

        unless request.valid?
          flash[:notice] = 'Please select 2 different journals.'
          routing.redirect '/'
        end

        result = Service::ListPapers.call(request)
        puts result

        if result.failure?
          flash[:error] = "API Error: #{result.message}"
          routing.redirect '/'
        end

        papers_page = Representer::PapersPageResponse.new(OpenStruct.new)
                                                     .from_json(result.message)
        response.expires 60, public: true
        view 'selected_journals',
             locals: {
               journals: papers_page.journals,
               papers: papers_page.papers.map { |p| AcaRadar::View::Paper.new(p) },
               research_interest_term: papers_page.research_interest_term,
               research_interest_2d: papers_page.research_interest_2d,
               pagination: {},
               error: nil
             }
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
