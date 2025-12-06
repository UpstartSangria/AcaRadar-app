# frozen_string_literal: true

module AcaRadar
  # class for processing api response
  class Response
    def initialize(http_response, error: false, message: nil)
      @http_response = http_response
      @is_connection_error = error
      @custom_message = message
    end

    def success?
      !@is_connection_error &&
        (200..299).include?(@http_response.code)
    end

    def failure?
      !success?
    end

    def message
      return @custom_message if @custom_message

      data = payload
      data['message'] || data['error'] || @http_response.reason
    rescue StandardError
      'Unknown Error'
    end

    def message_body
      payload
    end

    private

    def payload
      JSON.parse(@http_response.body.to_s)
    end
  end
end
