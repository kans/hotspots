require 'json'

require 'sinatra'
require 'haml'

require './repo'
require 'debugger'

$settings = {}
repos = {}

configure do
  $settings = JSON.parse(File.read 'settings.json')
  settings_repos = $settings['repos']

  settings_repos.each do |repo|
    repo = Repo.new(repo)
    repos[repo.org] = {} unless repos.has_key?(repo.org)
    repos[repo.org][repo.name] = repo
  end

  repos.each do |org, org_repos|
    org_repos.each do |name, repo|
      repo.set_hooks
      repo.spots = repo.find_hotspots
    end
  end
end


post "/api/:org/:name" do
  begin
    data = JSON.parse request.body.read
    org = "racker"
    name = "gutsy"
=begin
    action = data['action']
    unless action == 'opened'
      return
    end
    org = params[:org]
    name = params[:name]
=end
    repo = repos[org][name]
#    sha = data['head']['sha']
    sha = 'f0a33edde4c28ee29134a627e590abd6b1296f59'
    puts sha
    debugger
    repo.find_hotspots(sha)
  rescue Exception => e
    puts e
  ensure
    status 204
  end
end

get "/hotspots/:org/:name" do |org, name|
  haml :hotspots, locals:{ :repo => repos[name] }
end

get '/' do
  haml :index, locals:{ :repos => repos }
end
