require 'ostruct'
require 'uri'

require 'debugger'
require 'grit'
require 'github_api'

include FileUtils

class Repo < OpenStruct
  @@Fix = Struct.new(:message, :date, :files)
  @@Spot = Struct.new(:file, :score)

  def full_name()
    return "#{self.org}/#{self.name}"
  end

  def initialize(repo)
    super(repo)
    self.spots = nil
    self.dir = File.expand_path("#{$settings['repo_dir']}/#{self.org}/#{self.name}")
    puts self.dir
    mkdir_p(self.dir, mode: 0755)

    grit_repo = Grit::Git.new self.dir
    password = CGI::escape self.password
    process = grit_repo.clone({progress: true, process_info: true, timeout: 30},
      "https://#{self.login}:#{password}@github.com/#{self.org}/#{self.name}", self.dir)
    print process[2]
    self.pull()
  end

  def pull()
    grit_repo = Grit::Repo.new self.dir
    process = grit_repo.git.pull({progress: true, process_info: true}, self.dir)
    print process[2]
  end

  def set_hooks()
    puts "Setting hooks for #{self.full_name}"
    hook_url = URI.join $settings['address'], "/api/#{self.org}/#{self.name}"

    github = Github.new basic_auth: "#{self.login}:#{self.password}"
    hooks = github.repos.hooks.all self.org, self.name
    hooks_to_delete = []
    hooks.each do |hook|
      if hook.name == "web" and hook.config.url == hook_url then
        hooks_to_delete.push(hook)
      end
    end
    hooks_to_delete.each do |hook|
      github.repos.hooks.delete self.org, self.name, hook.id
    end
    github.repos.hooks.create self.org, self.name, name: "web", active: true, config:
      {url: hook_url, content_type: "json"}
  end

  def find_hotspots(branch='master')
    puts "Finding hotspots for #{self.full_name} #{branch}"
    regex = /fix(es|ed)?|close(s|d)?/i

    fixes = []
    grit_repo = Grit::Repo.new self.dir
    tree = grit_repo.tree(branch)
    commit_list = grit_repo.git.rev_list({:max_count => false, :no_merges => true, :pretty => "raw", :timeout => false}, branch)
    Grit::Commit.list_from_string(grit_repo, commit_list).each do |commit|
      if commit.message =~ regex
        # TODO: what does this line do?
        files = commit.stats.files.map {|s| s.first}.select{ |s| tree/s }
        fixes << @@Fix.new(commit.short_message, commit.date, files)
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
      @@Spot.new(spot.first, sprintf('%.4f', spot.last))
    end

    return spots
  end
end