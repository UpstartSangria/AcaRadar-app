# frozen_string_literal: true

require 'dry/monads'
require 'http'
require 'ostruct'

module AcaRadar
  module Service
    # class for list paper from api
    class ListPapers
      include Dry::Monads::Result::Mixin

      API_ROOT = ENV.fetch('API_HOST', 'http://localhost:9292/api/v1')

      def self.call(request)
        params = {}
        request.journals.each_with_index do |journal, index|
          params["journal#{index + 1}"] = journal
        end

        response = HTTP.headers(content_type: 'application/json')
                       .get("#{API_ROOT}/papers", params: params)

        Response.new(response)
      rescue HTTP::ConnectionError
        Response.new(nil, error: true, message: 'Connection to API refused')
      end
    end
  end
end
