#!/usr/bin/env ruby

require 'json'

require 'sinatra'
require 'haml'
require 'uri'
require 'oauth2'
require 'patron'

require './urls'
$settings = JSON.parse(File.read 'settings.json')

require './models'
require './helpers'
include Helpers

#require 'debugger'
require 'ruby-debug'
Debugger.wait_connection = true
Debugger.start_remote

projects = {}

configure do
  $DB[:projects].each do |db_project|
    debugger
    project = Project.new(db_project)
    projects[project.org] ||= {}
    projects[project.org][project.name] = project
  end
  projects.each do |org, org_projects|
    org_projects.each do |name, project|
      begin
        project.set_hooks
        project.add_events
      rescue Exception => e
        puts e, e.backtrace
      end
    end
  end
end

helpers do
  include Helpers
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

    project = projects[org] && projects[org][name]
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
  code = params[:code]

  query_string = {
    :client_id => $settings['client_id'],
    :client_secret => $settings['secret'],
    :code => code,
    :state => "project" }.map{|k,v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v)}"}.join("&")
  session = Patron::Session.new
  session.timeout = 10
  response = session.post "https://github.com/login/oauth/access_token", query_string
  return 'oh noes' if response.status >= 400
  body = CGI::parse response.body
  token = body.has_key?("access_token") && body["access_token"][0]
  response = session.get "https://api.github.com/user/repos?access_token=#{token}"
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
  @project = projects[org][name]
  spots = @project.get_hotspots
  @spots = Helpers::sort_hotspots(spots)

  if request.accept? 'text/html'
    return haml :hotspots
  else
    content_type :json
    return spots.to_json
  end
end


get '/' do
  haml :index, locals:{ :projects => projects }
end


get $urls[:HISTOGRAM] do
  @projects = projects
  haml :histogram
end
