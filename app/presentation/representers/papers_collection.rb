# frozen_string_literal: true

require 'ostruct'
require_relative 'paper'

module AcaRadar
  module Representer
    # class for the paper collections
    class PapersCollection < Representer::Base
      collection :data,
                 decorator: Representer::Paper,
                 class: OpenStruct
    end
  end
end
