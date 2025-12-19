# frozen_string_literal: true

require 'dry-monads'

module AcaRadar
  module Service
    # Service to embed a research interest term
    class EmbedResearchInterest
      include Dry::Monads::Result::Mixin

      API_ROOT = ENV.fetch('API_HOST', 'http://localhost:9292/api/v1')

      def self.call(request)
        data = { term: request.term }

        response = HTTP.headers(content_type: 'application/json')
                       .post("#{API_ROOT}/research_interest", json: data)

        Response.new(response)
      rescue HTTP::ConnectionError
        Response.new(nil, error: true, message: 'Connection to API refused')
      end
    end
  end
end
