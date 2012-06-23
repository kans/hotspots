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
    repos[repo.name] = repo
  end

  repos.each do |name, repo|
    repo.set_hooks
    repo.find_hotspots
  end
end


post "/api/:org/:name" do
  puts params
  params
end

get "/hotspots/:org/:name" do |org, name|
  haml :hotspots, locals:{ :repo => repos[name] }
end

get '/' do
  haml :index, locals:{ :repos => repos }
end
