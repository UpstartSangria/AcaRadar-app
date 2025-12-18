# frozen_string_literal: true

require 'roar/decorator'
require 'roar/json'

module AcaRadar
  module Representer
    # class for paper representer
    class Paper < Representer::Base
      property :origin_id
      property :title
      property :abstract
      property :pdf_url
      property :published_at

      # API sends a string
      property :authors

      # API sends an array of strings
      property :concepts

      # API sends {"x":..., "y":...} — keep as Hash
      property :embedding_2d

      property :similarity_score, render_nil: true
    end
  end
end
