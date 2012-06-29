require 'json'

require 'sinatra'
require 'haml'

require './repo'
require './db'
require './helpers'

$settings = {}
repos = {}

include Helpers

configure do
  $settings = JSON.parse(File.read 'settings.json')
  settings_repos = $settings['repos']

  settings_repos.each do |repo|
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

post "/api/:org/:name" do
  begin
    data = JSON.parse request.body.read
    action = data['action']
    unless action == 'opened'
      return
    end
    org = params[:org]
    name = params[:name]
    repo = repos[org][name]
    sha = data['head']['sha']
    puts sha

    hotspots = repo.get_hotspots(sha)
    puts hotspots
  rescue Exception => e
    puts e
  ensure
    status 204
  end
end


get "/hotspots/:org/:name" do |org, name|
  @threshold = (params[:threshold] || 0.5).to_f
  @repo = repos[org][name]
  spots = @repo.get_hotspots
  @spots = Helpers::sort_hotspots(spots)

  haml :hotspots
end

get "/hotspots/:org/:name/:from_sha/.?:to_sha?" do |org, name, from_sha, to_sha|
  @threshold = (params[:threshold] || 1.1).to_f
  @repo = repos[org][name]
  spots = @repo.get_hotspots
  filtered_spots = Hash.new

  files = @repo.get_files(from_sha, to_sha)
  files.each do |file|
    filtered_spots[file] = (spots.has_key?(file) ? spots[file] : 0.0)
  end

  @spots = Helpers::sort_hotspots(filtered_spots)

  haml :hotspots
end


get '/' do
  haml :index, locals:{ :repos => repos }
end


get '/histogram' do 
  @repos = repos
  haml :histogram 
end
