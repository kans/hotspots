require 'json'

require 'sinatra'
require 'github_api'

configure do
  settings = JSON.parse(File.read 'settings.json')
  org = settings['org']
  repo = settings['repo']
  address = settings['address']

  github = Github.new basic_auth: "#{settings['login']}:#{settings['password']}"
  hooks = github.repos.hooks.all org, repo
  hooks_to_delete = []
  hooks.each do |hook|
    if hook.name == "web" and hook.config.url == address then
      hooks_to_delete.push(hook)
    end
  end
  hooks_to_delete.each do |hook|
    puts 'deletig hook ', hook
    github.repos.hooks.delete org, repo, hook.id
  end
  github.repos.hooks.create org, repo, name: "web", active: true, config:
    {url: "#{address}/api/#{org}/#{repo}/#{settings['name']}", content_type: "json"}

  res = github.repos.commits.all org, repo, per_page: 100, page:1

  regex ||= /fix(es|ed)?|close(s|d)?/i

  to_fetch = []
  res.each_page do |page|
    page.each do |commit|
      if commit.commit.message =~ regex
        to_fetch.append(commit)
      end
    end
  end

  post "/api/:org/:repo/:name" do
    puts params
  end

end
