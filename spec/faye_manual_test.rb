# frozen_string_literal: true

# test_faye.rb
require 'net/http'
require 'json'
require 'uri'

# 1. PASTE YOUR REQUEST ID HERE
REQUEST_ID = '327819915725779479'

def send_progress(id, percent)
  uri = URI.parse('http://localhost:9292/faye')

  # Faye protocol expects this specific JSON structure
  message = {
    'channel' => "/#{id}",
    'data' => {
      'percent' => percent,
      'status' => 'working'
    }
  }

  Net::HTTP.post_form(uri, message: message.to_json)
  puts "Sent: #{percent}%"
end

puts "Sending test messages to channel /#{REQUEST_ID}..."
send_progress(REQUEST_ID, 10)
sleep 1
send_progress(REQUEST_ID, 50)
sleep 1
send_progress(REQUEST_ID, 100)
