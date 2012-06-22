require 'json'
require 'CGI'

require 'sinatra'
require 'github_api'
require 'debugger'
require 'grit'

include FileUtils

configure do
  settings = JSON.parse(File.read 'settings.json')
  org = settings['org']
  repo = settings['repo']
  address = settings['address']
  login = settings['login']
  password = CGI::escape settings['password']


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

  repo_dir = "#{settings['repo_dir']}/#{org}/#{repo}"
  mkdir_p(repo_dir, mode: 0755)
  grit_repo = Grit::Git.new repo_dir


  process = grit_repo.clone({progress: true, process_info: true},
    "https://#{login}:#{password}@github.com/#{org}/#{repo}", repo_dir)
  print process[2]
  fixes = []

  regex ||= /fix(es|ed)?|close(s|d)?/i

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



  paths = {}

  post "/api/:org/:repo/:name" do
    puts params
  end

end
