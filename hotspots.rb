#!/usr/bin/env ruby

require 'json'
require 'set'

require 'sinatra/synchrony'

require 'faraday'
require "em-synchrony/fiber_iterator"
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

  def get_project_by_id id
    project = nil
    id = id.to_i
    @@projects.each do |org, projects|
    projects.each do |name, _project|
      if _project.id == id
        project = _project
        break
      end
    end
    project
  end

  def self.add_project project
    @@projects[project.org] ||= {}
    @@projects[project.org][project.name] = project
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
    "responsible for showing a list of projects to add after querying github"
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
    @repos.sort_by! {|repo| repo["full_name"]}
    haml :select_repo
  end

  post $urls[:REMOVE_PROJECTS] do
    @projects = @@projects
    @removed = []
    repos = request.POST
    return redirect '/' unless repos
    repos.each do |id, on|
      project = self.get_project_by_id id
      @@projects[project.org].delete project.name
      if @@projects[project.org].keys.length == 0
        @@projects.delete project.org
      end
      project.uninstall
    end
    redirect '/'
  end

  post $urls[:ADD_REPOS] do
    #TODO: I think a sane approach would be to just have one function that does this for each repo, or perhaps for each 
    # incoming org.  Breaking it up into subfunctions looks difficult without a ton of passthrough .
    @added_repos = []
    repos = request.POST
    token = repos.delete "token"

    failed_to_add = Set.new
    org_to_repos_full_name = {}
    org_to_url = {}

    requests = []

    # get orgs from github
    repos.each do |full_name, clone_url|
      org, name = full_name.split "/"
      org_to_repos_full_name[org] ||= []
      org_to_repos_full_name[org] += [full_name]
      path = "/orgs/#{org}/teams"
      org_to_url[org] = path
      unless @@projects[org] && @@projects[org][name]
        requests << @@Request.new(full_name, path, { :access_token => token })
      end
    end

    return haml :added_users if requests.empty?

    successful_org_gets, errs = multi :aget, 'https://api.github.com', requests

    # add user to repos that aren't a org
    add_user_to_nonorg_requests = []
    repos_seen = []
    errs.select {|full_name, err| err.status == 404 }.each do |full_name, err|
      login = full_name.split('/')[0]
      org_to_repos_full_name[login].each do |repo|
        next if repos_seen.include? repo
        req = @@Request.new( repo,
          "/repos/#{repo}/collaborators/#{$settings["login"]}", {:access_token => token })
        add_user_to_nonorg_requests << req
        repos_seen << repo
      end
    end

    unless add_user_to_nonorg_requests.empty?
      good, bad = multi(:aput, 'https://api.github.com', add_user_to_nonorg_requests)
      failed_to_add += bad.keys
    end

    add_user_to_team = Set.new
    make_team_for_org = Set.new
    add_repo_to_team = {}
    successful_org_gets.each do |full_name, reply|
      create_team = true
      reply.body.each do |team|
        if team['name'] == $settings['team_name']
          create_team = false
          add_user_to_team << team["id"]
          add_repo_to_team[team['id']] = full_name
          break
        end
      end
      if create_team
        make_team_for_org << full_name.split('/')[0]
      end
    end

    unless add_repo_to_team.keys.empty?
      add_repo_requests = []
      add_repo_to_team.each do |team_id, full_name|
        add_repo_requests << @@Request.new(full_name, "/teams/#{team_id}/repos/#{full_name}", {:access_token => token })
      end
      callbacks, errbacks = multi :aput, 'https://api.github.com', add_repo_requests
    end

    # create teams
    unless make_team_for_org.empty?
      create_team_requests = []
      make_team_for_org.each do |org|
        create_team_requests << @@Request.new(org, [org_to_url[org]], {:access_token => token }, {
          :name => $settings['team_name'],
          :permission => "pull",
          :repo_names => org_to_repos_full_name[org]
        }, {"content-type"=> "application/json"})
      end

      callbacks, errbacks = multi :apost, 'https://api.github.com', create_team_requests

      # if we failed to make a team for an org, all repos failed
      errbacks.each {|org, value| failed_to_add += org_to_repos_full_name[org] }

      callbacks.each do |create_team_url, value|
        add_user_to_team << value.body['id']
      end
    end

    add_user_requests = []
    add_user_to_team.each do |team_id|
      add_user_requests << @@Request.new(team_id, "/teams/#{team_id}/members/#{$settings['login']}", {:access_token => token })
    end

    unless add_user_requests.empty?
      callbacks, errbacks = multi(:aput, 'https://api.github.com', add_user_requests)
    end

    @added_repos += repos.keys - failed_to_add.to_a
    @added_repos.each do |name|
      begin
        project = Project.new name, token
        project.save
        project.add_events
      rescue Sequel::DatabaseError => e
        @added_repos -= [name]
      else
        #TODO: move to a thread or something magical
        Hotspots.add_project project

      end
    end
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
  projects = Project.all
  next if projects.empty?
  EM.synchrony do
    res = []
    EM::Synchrony::FiberIterator.new(projects, 10).each do |project|
      operation = proc {
        Fiber.new{
          project.init_git
          project.add_events
        }.resume
        project
      }
      callback = proc {|project|
        res << project
        EM.stop() if res.length == projects.length
      }
      EM.defer( operation, callback )
    end
  end
  projects.each do |project|
    project.set_hooks
    Hotspots.add_project project
  end
end