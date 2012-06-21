require 'json'

require 'sinatra'
require 'github_api'

def install_hooks
  settings = JSON.parse(File.read 'settings.json')
  puts  login: settings['login'], password: settings['password']
  github = Github.new basic_auth: "#{settings['login']}:#{settings['password']}"
  hooks = github.repos.hooks.all 'racker', 'reach'
  exit(0)
end

configure do  install_hooks
end
