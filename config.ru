require 'sinatra'
require 'sinatra/synchrony'
require 'faraday'
Faraday.default_adapter = :em_synchrony

require './models'
require './helpers'
include Helpers
require './hotspots'
#include Hotspots

$settings = JSON.parse(File.read 'settings.json')

configure do
  Project.all.each do |project|
    Hotspots.add_project project
  end
end

helpers do
  include Helpers
end

Hotspots.run!