# frozen_string_literal: true

require_relative 'paper'

module AcaRadar
  module Representer
    # class for the paper collections
    class PapersCollection < Representer::Base
      collection :data,
                 decorator: Representer::Paper
    end
  end
end
