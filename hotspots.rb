#!/usr/bin/env ruby

require 'json'

require 'sinatra'
require 'sinatra/synchrony'
require 'faraday'

require 'haml'
require 'uri'
require 'oauth2'

require './urls'


require 'debugger'
#require 'ruby-debug'
# Debugger.wait_connection = true
# Debugger.start_remote

class Hotspots < Sinatra::Base
  @@projects = {}

  register Sinatra::Synchrony
  
  def self.add_project project
    @@projects[project.org] ||= {}
    @@projects[project.org][project.name] = project
    begin
      project.init_git
      project.add_events
      project.set_hooks
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
    response = Faraday.new(:url => 'https://api.github.com').get "/user/repos", { 
      :access_token => token }
    return 'oh noes' if response.status >= 400
    @repos = JSON.parse response.body
    # XXXX: Make sure this is over HTTPS!
    @token = token
    haml :select_repo
  end


  post $urls[:ADD_REPOS] do
    repos = request.POST
    token = repos.delete "token"

    repos.each do |repo, clone_url|
      org, name = repo.split "/"
      project = Project.new(org, name, clone_url, token)
      project.save
    end

    redirect "/", 302
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


