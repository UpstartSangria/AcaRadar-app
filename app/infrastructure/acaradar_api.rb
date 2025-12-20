# frozen_string_literal: true

require 'http'
require_relative 'response'

module AcaRadar
  # Gateway class to talk to the API
  class Api
    API_ROOT = ENV.fetch('API_URL', 'http://localhost:9292/api/v1')

    def self.embed_interest(request)
      data = { term: request.term }

      response = HTTP.headers(content_type: 'application/json')
                     .post("#{API_ROOT}/research_interest", json: data)

      Response.new(response)
    rescue HTTP::ConnectionError
      Response.new(nil, error: true, message: 'Connection to API refused')
    end

    def self.list_papers(request)
      params = {}
    
      # New contract fields (if your request object provides them)
      params['request_id'] = request.request_id if request.respond_to?(:request_id) && request.request_id
    
      if request.respond_to?(:journals) && request.journals
        params['journals[]'] = Array(request.journals)
      else
        # Legacy fallback (journal1/journal2)
        Array(request.journals).each_with_index do |journal, index|
          params["journal#{index + 1}"] = journal
        end
      end
    
      params['top_n']    = request.top_n    if request.respond_to?(:top_n) && request.top_n
      params['min_date'] = request.min_date if request.respond_to?(:min_date) && request.min_date
      params['max_date'] = request.max_date if request.respond_to?(:max_date) && request.max_date
    
      response = HTTP.headers(content_type: 'application/json')
                     .get("#{API_ROOT}/papers", params: params)
    
      Response.new(response)
    rescue HTTP::ConnectionError
      Response.new(nil, error: true, message: 'Connection to API refused')
    end    
  end
end
