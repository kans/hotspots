#!/usr/bin/env ruby
require 'json'

require 'sinatra'
require 'haml'
require 'uri'

require './repo'
require './db'
require './helpers'

$settings = {}
repos = {}

include Helpers

configure do
  $settings = JSON.parse(File.read 'settings.json')

  $settings['repos'].each do |repo|
    repo = Repo.new(repo)
    repos[repo.org] ||= {}
    repos[repo.org][repo.name] = repo
  end
  repos.each do |org, org_repos|
    org_repos.each do |name, repo|
      repo.set_hooks
      repo.add_events
    end
  end
end

helpers do
  include Helpers
end

post "/api/:org/:name" do |org, name|
  begin
    data = JSON.parse request.body.read
    action = data['action']
    puts data
    unless action == 'opened'
      return
    end
    repo = repos[org][name]

    sha = data['pull_request']['head']['sha']
    puts sha

    spots = Helpers::sort_hotspots(repo.get_hotspots)
    filtered_spots = repo.get_hotspots_for_sha(sha)
    puts spots

    comment = haml :comment,
                   locals:{ :repo => repo,
                            :spots => spots,
                            :filtered_spots => filtered_spots,
                            :sha => sha}
    puts comment
    repo.comment(data['number'], comment.to_s)
  rescue Exception => e
    puts e
    puts e.backtrace
  ensure
    status 204
  end
end

get %r{/hotspots/(?<org>\w+)/(?<name>\w+)}, :provides => :json do |org, name|
  pass unless request.accept? 'application/json'
  debugger
  content_type :json  
  spots = repos[org][name].get_hotspots
  spots.to_json
end

get '/hotspots/:org/:name' do |org, name|
  @threshold = (params[:threshold] || 0.5).to_f
  @repo = repos[org][name]
  spots = @repo.get_hotspots
  @spots = Helpers::sort_hotspots(spots)
  haml :hotspots
end

get '/' do
  haml :index, locals:{ :repos => repos }
end


get '/histogram' do
  @repos = repos
  haml :histogram
end
