#!/usr/bin/env ruby

require 'json'
require 'set'

require 'sinatra/synchrony'

require 'faraday'
require "em-synchrony/em-http"

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
  @@Request = Struct.new :name, :url, :path, :query, :body, :headers
  @@projects ||= {}

  configure :development do
  end

  register Sinatra::Synchrony

  helpers do
    include Helpers
  end

  before do
    content_type 'text/html'
  end

  def multi method, requests
    multi = EventMachine::Synchrony::Multi.new
    requests.each do |request|
      multi.add request.name, EventMachine::HttpRequest.new(request.url).send(method, Hash[request.each_pair.to_a])
    end
    return multi.perform.responses.values
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

    org_to_repos = {}
    org_to_url = {}
    requests = []

    repos.each do |repo, clone_url|
      org, name = repo.split "/"
      org_to_repos[org] ||= []
      org_to_repos[org] += [repo]
      path = "/orgs/#{org}/teams"
      org_to_url[org] = path
      requests << @@Request.new(org, 'https://api.github.com', path, { :access_token => token })
    end

    callbacks, errbacks = multi :aget, requests

    add_user_to_team = []
    teams_to_make = []
    callbacks.each do |org, value|
      next if value.response_header["STATUS"].split[0].to_i >= 400
      # TODO: nexti if value.not json!
      json = JSON.parse value.response
      create_team = true
      json.each do |team|
        if team['name'] == $settings['team_name']
          create_team = false
          add_user_to_team << team["id"] #/teams/#{team['id']}/members/#{$settings['login']}"
          break
        end
      end
      if create_team
        teams_to_make << org
      end
    end

    # create teams
    unless teams_to_make.empty?
      requests = []
      teams_to_make.each do |org|
        requests << @@Request.new(org, 'https://api.github.com', [org_to_url[org]], {:access_token => token }, {
          :name => $settings['team_name'],
          :permission => "pull",
          :repo_names => org_to_repos[org]
        }, {"content-type"=> "application/json"})
      end

      callbacks, errbacks = multi :apost, requests

      callbacks.each do |create_team_url, value|
        next if value.response_header["STATUS"].split[0].to_i >= 400
        json = JSON.parse value.response
        add_user_to_team << json['id']
      end
    end

    requests = []
    add_user_to_team.each do |team_id|
      requests << @@Request.new(team_id,'https://api.github.com', "/teams/#{team_id}/members/#{$settings['login']}", {:access_token => token })
    end

    @callbacks, @errbacks = multi(:aput, requests)

    haml :added_users
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
