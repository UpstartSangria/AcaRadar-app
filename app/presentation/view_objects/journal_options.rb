# frozen_string_literal: true

require 'http'
require 'json'

module AcaRadar
  module View
    # Presents journal options in the frontend (fetched from API)
    class JournalOption
      FALLBACK = [
        ['MIS Quarterly', 'MIS Quarterly'],
        ['Management Science', 'Management Science'],
        ['Journal of the ACM', 'Journal of the ACM']
      ].freeze

      def self.all
        api_base = ENV.fetch('ACARADAR_API_URL', ENV.fetch('API_URL', 'http://localhost:9292')).to_s.sub(%r{/\z}, '')
        url = "#{api_base}/api/v1/journals"

        resp = HTTP.get(url)
        return FALLBACK unless resp.status.success?

        raw = JSON.parse(resp.to_s) rescue {}
        data = raw.is_a?(Hash) ? (raw['data'] || {}) : {}

        names = extract_journal_names(data)

        return FALLBACK if names.empty?


        names.map { |n| [n, n] }
      rescue StandardError => e
        warn "[JournalOption] Failed to fetch journals: #{e.class}: #{e.message}"
        FALLBACK
      end

      def self.extract_journal_names(data)
        # Shape A (older): { journals: ["MIS Quarterly", ...] }
        direct = Array(data['journals'])
        names =
          if direct.any?
            direct
          else
            # Shape B (current API): { domains: [ { journals: [...] }, ... ] }
            domains = Array(data['domains'])
            domains.flat_map { |d| Array(d.is_a?(Hash) ? d['journals'] : nil) }
          end
      
        names
          .map { |x| x.to_s.strip }
          .reject(&:empty?)
          .uniq
          .sort
      end
      private_class_method :extract_journal_names
      
    end
  end
end
