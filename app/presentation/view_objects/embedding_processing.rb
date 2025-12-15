# frozen_string_literal: true

module AcaRadar
  module View
    # View for presenting embedding status
    class EmbeddingProcessing
      attr_reader :response

      def initialize(config, response)
        @config = config
        @response = response
        @data = response.fetch('data', {})
      end

      def in_progress?
        response['status'] == 'accepted'
      end

      def ws_channel_id
        @data['channel_id'] if in_progress?
      end

      def ws_javascript
        "#{@config.API_HOST}/faye/client.js" if in_progress?
      end

      def ws_route
        "#{@config.API_HOST}/faye" if in_progress?
      end
    end
  end
end
