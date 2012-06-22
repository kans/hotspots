require 'json'

require 'sinatra'
require 'github_api'
require 'debugger'
require 'grit'

configure do
  settings = JSON.parse(File.read 'settings.json')
  org = settings['org']
  repo = settings['repo']
  address = settings['address']

  hook_url = "#{address}/api/#{org}/#{repo}/#{settings['name']}"

  github = Github.new basic_auth: "#{settings['login']}:#{settings['password']}"
  hooks = github.repos.hooks.all org, repo
  hooks_to_delete = []
  hooks.each do |hook|
    if hook.name == "web" and hook.config.url == hook_url then
      hooks_to_delete.push(hook)
    end
  end
  hooks_to_delete.each do |hook|
    github.repos.hooks.delete org, repo, hook.id
  end
  github.repos.hooks.create org, repo, name: "web", active: true, config:
    {url: hook_url, content_type: "json"}

  regex ||= /fix(es|ed)?|close(s|d)?/i

  Fix = Struct.new(:message, :date, :files)
  Spot = Struct.new(:file, :score)

  grit = Grit::Repo.new "repos/#{repo}"
  grit.clone({:branch => 'origin/master'},"git://github.com/#{org}/#{repo}.git", "repos/#{repo}")

  fixes = []

  regex ||= /fix(es|ed)?|close(s|d)?/i

  tree = grit.tree('master')

  commit_list = grit.git.rev_list({:max_count => false, :no_merges => true, :pretty => "raw", :timeout => false}, branch)
  Grit::Commit.list_from_string(grit, commit_list).each do |commit|
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



  paths = {}

  post "/api/:org/:repo/:name" do
    puts params
  end

end
