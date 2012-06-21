require 'json'

require 'sinatra'
require 'github_api'

def handle_hooks
  settings = JSON.parse(File.read 'settings.json')
  puts  login: settings['login'], password: settings['password']
  github = Github.new basic_auth: "#{settings['login']}:#{settings['password']}"
  hooks = github.repos.hooks.all 'racker', 'reach'
  hooks_to_delete = []
  hooks.each do |hook|
    if hook.name == "web" and hook.config.url == settings['address'] then
      hooks_to_delete.push(hook)
    end
  end
  hooks_to_delete.each do |hook|
    puts 'deletig hook ', hook
    github.repos.hooks.delete 'racker', 'reach', hook.id
  end
  github.repos.hooks.create 'racker', 'reach', name: "web", active: true, config:
    {url: settings['address'], content_type: "json"}
end

configure do handle_hooks
end
