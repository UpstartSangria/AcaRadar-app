# frozen_string_literal: true

require 'date'
require_relative 'base'

module AcaRadar
  module Request
    # Request validator for listing papers (1+ journals, optional top_n and date range)
    class ListPapers < Base
      MAX_TOP_N = 200

      def journals
        @journals ||= begin
          raw = params['journals'] || params['journals[]']

          values =
            if raw
              raw.is_a?(Array) ? raw : raw.to_s.split(',')
            else
              # Backward compat: journal1, journal2, ...
              kv = params.select { |k, _| k.to_s.match?(/\Ajournal\d+\z/) }
              kv.sort_by { |k, _| k.to_s.sub('journal', '').to_i }.map { |_, v| v }
            end

          values.map { |v| v.to_s.strip }.reject(&:empty?).uniq
        end
      end

      def page
        raw = params['page'].to_s.strip
        return 1 if raw.empty?

        i = raw.to_i
        i < 1 ? 1 : i
      end

      def request_id
        (params['request_id'] || params['job_id']).to_s.strip
      end

      def top_n_raw
        params['top_n'] || params['n']
      end

      def top_n
        s = top_n_raw.to_s.strip
        return nil if s.empty?
        return nil unless s.match?(/\A[1-9]\d*\z/)

        [s.to_i, MAX_TOP_N].min
      end

      def min_date
        @min_date ||= parse_iso_date(params['min_date'])
      end

      def max_date
        @max_date ||= parse_iso_date(params['max_date'])
      end

      def valid?
        return false if journals.empty?

        # top_n must be valid if provided
        raw_top = top_n_raw.to_s.strip
        return false if !raw_top.empty? && top_n.nil?

        # top_n requires embedded research interest
        return false if top_n && request_id.empty?

        return false unless date_range_valid?

        true
      end

      def error_message
        return 'You must select at least one journal' if journals.empty?

        raw_top = top_n_raw.to_s.strip
        return 'top_n must be a positive integer' if !raw_top.empty? && top_n.nil?
        return "Top N requires an embedded research interest (request_id). Please click 'Embed' first." if top_n && request_id.empty?

        return 'min_date and max_date must be in YYYY-MM-DD format' if min_date == :invalid || max_date == :invalid
        return 'min_date must be <= max_date' unless date_range_valid?

        nil
      end

      # IMPORTANT: return PAIRS so api_request can build journals[] properly
      def to_query_params_pairs
        pairs = []

        journals.each { |j| pairs << ['journals[]', j] }

        pairs << ['page', page] if params.key?('page')
        pairs << ['request_id', request_id] unless request_id.empty?
        pairs << ['top_n', top_n] if top_n

        md = params['min_date'].to_s.strip
        xd = params['max_date'].to_s.strip
        pairs << ['min_date', md] unless md.empty?
        pairs << ['max_date', xd] unless xd.empty?

        pairs
      end

      private

      def parse_iso_date(raw)
        s = raw.to_s.strip
        return nil if s.empty?

        Date.iso8601(s)
      rescue ArgumentError
        :invalid
      end

      def date_range_valid?
        return false if min_date == :invalid || max_date == :invalid
        return true if min_date.nil? || max_date.nil?

        min_date <= max_date
      end
    end
  end
end
