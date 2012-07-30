#!/usr/bin/env ruby

require 'json'

require 'sinatra'
require 'haml'
require 'uri'
require 'oauth2'
require 'patron'

require './models'
require './helpers'

$settings = {}
projects = {}

include Helpers

configure do
  $settings = JSON.parse(File.read 'settings.json')

  $DB[:projects].each do |db_project|
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

post "/api/:org/:name" do |org, name|
  begin
    data = JSON.parse request.body.read
    action = data['action']
    puts data
    unless action == 'opened'
      return
    end
    project = projects[org][name]

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
    status 204
  end
end

get '/oauth/:org/:name' do |org, name|
  # project = projects[org] && projects[org][name]
  return haml :oauth, locals:{ :org => org, :name => name}
end

get '/oauth/callback/:org/:name' do |org, name|
  code = params[:code]
  
  query_string = {
    :client_id => $settings['client_id'],
    :client_secret => $settings['secret'],
    :code => code,
    :state => "project" }.map{|k,v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v)}"}.join("&")
  response = Patron::Session.new.post "https://github.com/login/oauth/access_token", query_string
  return 'oh noes' unless response.status == 200
  body = CGI::parse response.body
  token = body.has_key?("access_token") && body["access_token"][0]
end 

get '/hotspots/:org/:name' do |org, name|

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

get '/histogram' do
  @projects = projects
  haml :histogram
end
