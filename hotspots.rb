require 'json'

require 'sinatra'
require 'haml'

require './repo'
require 'debugger'
require 'sqlite3'

$settings = {}
repos = {}

configure do
  $db = SQLite3::Database.new('db.sqlite')
  $db.execute "
  CREATE TABLE IF NOT EXISTS projects (
    id INTEGER PRIMARY KEY NOT NULL,
    org VARCHAR(40) NOT NULL,
    repo VARCHAR(40) NOT NULL,
    head VARCHAR(40) NOT NULL,
    UNIQUE(repo, org)
  );"
  $db.execute "
  CREATE TABLE IF NOT EXISTS events (
    project_id REFERENCES projects(id) NOT NULL,
    time TIMESTAMP NOT NULL,
    sha VARCHAR(40),
    path TEXT NOT NULL,
    UNIQUE(sha, path)
  );
  "

  $settings = JSON.parse(File.read 'settings.json')
  settings_repos = $settings['repos']

  settings_repos.each do |repo|
    repo = Repo.new(repo)
    begin
      $db.execute "INSERT INTO PROJECTS (org, repo, head) VALUES(?, ?, ?);", repo.org, repo.name, ""
    rescue SQLite3::ConstraintException => e
    end

    repos[repo.org] ||= {}
    repos[repo.org][repo.name] = repo
  end
  repos.each do |org, org_repos|
    org_repos.each do |name, repo|
      repo.set_hooks
      repo.set_hotspots
    end
  end
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
    hotspots = repo.get_hotspots(sha: sha)
    puts hotspots
  rescue Exception => e
    puts e
  ensure
    status 204
  end
end


get "/hotspots/:org/:name/?:sha?" do |org, name, sha|
  repo = repos[org][name]
  spots = repo.get_hotspots(sha)
  haml :hotspots, locals:{ :repo => repo, :spots => spots }
end

get '/' do
  haml :index, locals:{ :repos => repos }
end
