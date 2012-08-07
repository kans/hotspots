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
  
  register Sinatra::Synchrony

  @@projects ||= {}
  @@Request = Struct.new :name, :path, :query, :body, :headers
  @@Response = Struct.new(:body, :path, :status, :headers) do 
    def initialize response
      args = []

      begin
        body = JSON.parse response.response
      rescue
        body = response.response
      end
      
      args << body
      args << response.req.path
      args << response.response_header["STATUS"].split[0].to_i
      args << response.response_header

      super(*args)
    end
  end
  
  configure :development do
  end

  helpers do
    include Helpers
  end

  before do
    content_type 'text/html'
  end

  def multi method, host, requests
    multi = EventMachine::Synchrony::Multi.new
    requests.each do |request|
      multi.add request.name, EventMachine::HttpRequest.new(host).send(method, Hash[request.each_pair.to_a])
    end
    callbacks, errbacks = multi.perform.responses.values

    res = {}; errs = {}
    callbacks.each do |key, value|
      if value.response_header["STATUS"].split[0].to_i < 400
        res[key] =  @@Response.new value
      else
        errs[key] = @@Response.new value
      end
    end
    
    errbacks.each do |key, value|
      errs[key] = @@Response.new value
    end
    return [res, errs]
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

    @repos_added = {:success => {}, :failed => {}}

    org_to_repos_full_name = {}
    org_to_url = {}
    requests = []

    # get orgs from github
    repos.each do |repo, clone_url|
      org, name = repo.split "/"
      org_to_repos_full_name[org] ||= []
      org_to_repos_full_name[org] += [repo]
      path = "/orgs/#{org}/teams"
      org_to_url[org] = path
      requests << @@Request.new(org, path, { :access_token => token })
    end

    successful_org_gets, errs = multi :aget, 'https://api.github.com', requests

    #TODO: use function to reduce variable spanning
    # add user to repos that aren't a org
    requests = []
    errs.select {|login, err| err.status == 404 }.each do |login, err|
      org_to_repos_full_name[login].each do |repo|
        requests << @@Request.new( repo, "/repos/#{repo}/collaborators/#{$settings["login"]}", {:access_token => token })
      end
    end
    
    unless requests.empty?
      good, bad = multi(:aput, 'https://api.github.com', requests)
      @repos_added[:success].merge! good
      @repos_added[:failed].merge! bad
    end
    
    add_user_to_team = []
    make_team_for_org = []
    successful_org_gets.each do |org, reply|
      create_team = true
      reply.body.each do |team|
        if team['name'] == $settings['team_name']
          create_team = false
          add_user_to_team << team["id"]
          break
        end
      end
      if create_team
        make_team_for_org << org
      end
    end

    # create teams
    unless make_team_for_org.empty?
      requests = []
      make_team_for_org.each do |org|
        requests << @@Request.new(org, [org_to_url[org]], {:access_token => token }, {
          :name => $settings['team_name'],
          :permission => "pull",
          :repo_names => org_to_repos_full_name[org]
        }, {"content-type"=> "application/json"})
      end

      callbacks, errbacks = multi :apost, 'https://api.github.com', requests

      callbacks.each do |create_team_url, value|
        add_user_to_team << value.body['id']
      end
    end

    requests = []
    add_user_to_team.each do |team_id|
      requests << @@Request.new(team_id, "/teams/#{team_id}/members/#{$settings['login']}", {:access_token => token })
    end

    good, bad = multi(:aput, 'https://api.github.com', requests)
    @repos_added[:success].merge! good
    @repos_added[:failed].merge! bad

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
