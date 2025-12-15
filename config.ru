# frozen_string_literal: true

require_relative 'require_app'
require 'faye'
require_app

# use keyword use to apply Faye as middleware
use Faye::RackAdapter, mount: '/faye', timeout: 25
run AcaRadar::App.freeze.app
