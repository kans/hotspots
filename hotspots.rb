#!/usr/bin/env ruby

require 'json'
require 'set'

require 'sinatra/async'
require 'faraday'
require 'sinatra/synchrony'
#require "em-synchrony"
require "em-synchrony/em-http"
require "em-synchrony/fiber_iterator"

require 'haml'
require 'uri'
require 'oauth2'
require 'sequel'

$settings = JSON.parse(File.read 'settings.json')

require './helpers'
include Helpers

require './models'
require './urls'
  
require 'debugger'
#require 'ruby-debug'
# Debugger.wait_connection = true
# Debugger.start_remote


class Hotspots < Sinatra::Base
  @@projects ||= {}

  configure :development do
  end

  register Sinatra::Async
  register Sinatra::Synchrony

  helpers do
    include Helpers
  end

  before do
    content_type 'text/html'
  end

  def self.add_project project
    @@projects[project.org] ||= {}
    @@projects[project.org][project.name] = project
    begin
      project.init_git
      # project.add_events
      # project.set_hooks
    rescue Exception => e
      puts e, e.backtrace
    end
  end

  get '/' do
    haml :index, locals:{ :projects => @@projects }
  end

  post $urls[:GITHUB_HOOK] do |org, name|
    @status = 204
    begin
      data = JSON.parse request.body.read
      action = data['action']
      puts data
      unless action == 'opened'
        return
      end

      project = @@projects[org] && @@projects[org][name]
      unless project
        @status = 404
        return
      end

      sha = data['pull_request']['head']['sha']
      puts sha

      spots = Helpers::sort_hotspots(project.get_hotspots)
      filtered_spots = project.get_hotspots_for_sha(sha)
      puts spots

      comment = haml :comment,
                     locals:{ :project => project,
                              :spots => spots,
                              :filtered_spots => filtered_spots,
                              :sha => sha}
      puts comment
      project.comment(data['number'], comment.to_s)
    rescue Exception => e
      puts e, e.backtrace
    ensure
      status @status
    end
  end


  get $urls[:OAUTH_CALLBACK] do
    @repos = []
    conn = Faraday.new(:url => 'https://github.com')
    response = conn.post '/login/oauth/access_token', {
      :client_id => $settings['client_id'],
      :client_secret => $settings['secret'],
      :code => params[:code],
      :state => "project"
    }
    return 'oh noes' if response.status >= 400
    body = CGI::parse response.body
    token = body.has_key?("access_token") && body["access_token"][0]
    conn = Faraday.new(:url => 'https://api.github.com')
    response = conn.get "/user/orgs", { 
      :access_token => token }
    orgs = JSON.parse response.body
    orgs.each do |org|
      response = conn.get "/orgs/#{org["login"]}/repos", { 
        :access_token => token }
      @repos += JSON.parse(response.body)
    end
    response = conn.get "/user/repos", {
      :access_token => token }
    return 'oh noes' if response.status >= 400
    @repos += JSON.parse(response.body)
    @repos.each do |repo|
      org = repo["owner"]["login"]
      name = repo["name"]
      repo["checked"] = true if @@projects.has_key?(org) && @@projects[org].has_key?(name)
    end
    # XXXX: Make sure this is over HTTPS!
    @token = token
    haml :select_repo
  end


  post $urls[:ADD_REPOS] do
    repos = request.POST
    token = repos.delete "token"
    orgs = {}
    urls = Set.new

    repos.each do |repo, clone_url|
      org, name = repo.split "/"
      orgs[org] ||= []
      orgs[org] += [repo]
      urls <<  "/orgs/#{org}/teams"
    end

    multi = EventMachine::Synchrony::Multi.new
    _redirect = Proc.new {
      #p multi.responses[:callback][:"/orgs/racker/teams"]
      debugger
      redirect "/", 302
    }

    EventMachine.synchrony do
      http = EventMachine::HttpRequest.new('https://api.github.com')
      urls.each do |url|
        multi.add url, http.aget( path: url, query: { :access_token => token })
      end
      multi.callback &_redirect
      multi.perform
      EventMachine.stop
    end
    # teams = {}
    # orgs.each do |org, repos|
    #   response = conn.get "/orgs/#{org}/teams", {
    #     :access_token => token }
    #   teams[org] = 
    # end
    # teams_to_make = []
    # teams.each do |org, teams_array|
    #   create_team = true
    #   teams_array.each do |team|
    #     # THIS IS BROKEN
    #     if team['name'] == $settings['team_name']
    #       create_team = false
    #       break
    #     end
    #   end
    #   if create_team
    #     teams_to_make <<  ["/orgs/#{org}/teams", {
    #       :name => $settings['team_name'],
    #       :permission => "pull",
    #       :repo_names => orgs[org]
    #     }]
    #   end
    # end

    # debugger

    # EM.synchrony do
    #   urls = ['http://url.1.com', 'http://url2.com']
    #   results = []

    #   EM::Synchrony::FiberIterator.new(urls, 5).each do |url|
    #       resp = EventMachine::HttpRequest.new(url).get
    #   results.push resp.response
    # end

    # p results # all completed requests

    # repos.each do |repo, clone_url|
    #   org, name = repo.split "/"
    #   project = Project.new(org, name, clone_url, token)
    #   begin
    #     project.save
    #   rescue Sequel::DatabaseError
    #   else
    #     Hotspots.add_project project
    #   end
    # end

  end


  get $urls[:HOTSPOTS] do |org, name|
    @threshold = (params[:threshold] || 0.5).to_f
    @project = @@projects[org][name]
    spots = @project.get_hotspots
    @spots = Helpers::sort_hotspots(spots)

    if request.accept? 'text/html'
      return haml :hotspots
    else
      content_type :json
      return spots.to_json
    end
  end

  get $urls[:HISTOGRAM] do
    @projects = @@projects
    haml :histogram
  end
end


configure do
  Project.all.each do |project|
    Hotspots.add_project project
  end
end
