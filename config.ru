require 'sinatra'
require 'sinatra/synchrony'

enable :logging
set :environment, :development
set :port, 4567

require 'faraday'
Faraday.default_adapter = :em_synchrony

require './hotspots'
Hotspots.run!
