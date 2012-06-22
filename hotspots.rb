require 'json'
require 'CGI'

require 'sinatra'
require 'github_api'
require 'debugger'
require 'grit'
require 'haml'

include FileUtils

configure do
  settings = JSON.parse(File.read 'settings.json')
  org = settings['org']
  repo = settings['repo']
  address = settings['address']
  login = settings['login']
  password = CGI::escape settings['password']

  all_hotspots = {}

  hook_url = "#{address}/api/#{org}/#{repo}/#{settings['name']}"

  # github = Github.new basic_auth: "#{settings['login']}:#{settings['password']}"
  # hooks = github.repos.hooks.all org, repo
  # hooks_to_delete = []
  # hooks.each do |hook|
  #   if hook.name == "web" and hook.config.url == hook_url then
  #     hooks_to_delete.push(hook)
  #   end
  # end
  # hooks_to_delete.each do |hook|
  #   github.repos.hooks.delete org, repo, hook.id
  # end
  # github.repos.hooks.create org, repo, name: "web", active: true, config:
  #   {url: hook_url, content_type: "json"}

  regex ||= /fix(es|ed)?|close(s|d)?/i

  Fix = Struct.new(:message, :date, :files)
  Spot = Struct.new(:file, :score)

  repo_dir = File.join(settings['repo_dir'], "#{org}/#{repo}")
  puts repo_dir
  mkdir_p(repo_dir, mode: 0755)

  grit_repo = Grit::Git.new repo_dir
  process = grit_repo.clone({progress: true, process_info: true},
    "https://#{login}:#{password}@github.com/#{org}/#{repo}", repo_dir)
  print process[2]

  branch = 'master'
  fixes = []
  grit_repo = Grit::Repo.new repo_dir
  tree = grit_repo.tree(branch)
  commit_list = grit_repo.git.rev_list({:max_count => false, :no_merges => true, :pretty => "raw", :timeout => false}, branch)
  Grit::Commit.list_from_string(grit_repo, commit_list).each do |commit|
    if commit.message =~ regex
      files = commit.stats.files.map {|s| s.first}.select{ |s| tree/s }
      fixes << Fix.new(commit.short_message, commit.date, files)
    end
  end

  hotspots = Hash.new(0)
  fixes.each do |fix|
    fix.files.each do |file|
      t = 1 - ((Time.now - fix.date).to_f / (Time.now - fixes.last.date))
      hotspots[file] += 1/(1+Math.exp((-12*t)+12))
    end
  end

  spots = hotspots.sort_by {|k,v| v}.reverse.collect do |spot|
    Spot.new(spot.first, sprintf('%.4f', spot.last))
  end

  if all_hotspots[org] == nil
    all_hotspots[org] = {}
  end
  all_hotspots[org][repo] = spots

  post "/api/:org/:repo/:name" do
    puts params
    params
  end

  get "/hotspots/:org/:repo" do
    haml :hotspots, locals:{ :hotspots => all_hotspots[org][repo], :org => org, :repo => repo }
  end

  get '/' do
    haml :index, locals:{ :all_hotspots => all_hotspots }
  end
end
