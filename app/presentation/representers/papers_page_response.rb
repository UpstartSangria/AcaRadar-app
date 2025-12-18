# frozen_string_literal: true

require 'roar/decorator'
require 'roar/json'
require 'ostruct'

require_relative 'base'
require_relative 'papers_collection'

module AcaRadar
  module Representer
    # class for paper page response
    class PapersPageResponse < Representer::Base
      include Roar::JSON

      property :research_interest_term
      property :research_interest_2d
      property :journals

      property :papers,
               decorator: Representer::PapersCollection,
               pass_options: true,
               class: OpenStruct

      property :pagination
    end
  end
end
