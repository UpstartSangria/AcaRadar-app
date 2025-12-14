# frozen_string_literal: true

require 'time'

module AcaRadar
  module View
    class Paper
      def initialize(entity)
        @entity = entity
      end

      def pdf_url
        @entity.pdf_url
      end

      def title
        @entity.title
      end

      def published
        Time.parse(@entity.published_at.to_s).strftime('%Y-%m-%d')
      rescue StandardError
        @entity.published_at.to_s
      end

      def authors_list
        a = @entity.authors
        return '' if a.nil? || a.to_s.strip.empty?
        return a if a.is_a?(String)

        Array(a).join(', ')
      end

      def short_summary
        @entity.abstract.to_s
      end

      def concepts_list
        Array(@entity.concepts).join(', ')
      end

      # you don’t have a full embedding vector in this JSON; show 2D
      def short_embedding
        emb = two_dim_embedding
        return '' unless emb

        "x=#{emb[0]}, y=#{emb[1]}"
      end

      def two_dim_embedding
        emb = @entity.embedding_2d
        return nil unless emb

        if emb.is_a?(Hash)
          [emb['x'] || emb[:x], emb['y'] || emb[:y]]
        elsif emb.is_a?(Array)
          emb
        end
      end
    end
  end
end
