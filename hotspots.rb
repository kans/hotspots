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
    {url: address, content_type: "json"}
end
