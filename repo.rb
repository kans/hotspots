require 'ostruct'
require 'uri'

require 'debugger'
require 'grit'
require 'github_api'
require './db'

include FileUtils

class Repo < OpenStruct
  @@Spot = Struct.new(:file, :score)
  @@Fix = Struct.new(:date, :sha, :file)
  @@opts = {:max_count => false, :no_merges => true, :pretty => "raw", :timeout => false}

  def full_name()
    return "#{self.org}/#{self.name}"
  end

  def initialize(repo)
    super(repo)
    self.hotspots = Hash.new(0)
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


  def add_events()
    puts 'setting spots for ' + self.name
    regex = /fix(es|ed)?|close(s|d)?/i
    grit_repo = Grit::Repo.new self.dir
    tree = grit_repo.tree("master")
    last_sha = DB::get_last_sha self
    args = []
    if last_sha
      args << "^#{last_sha}"
    end
    args << 'master'
    commit_list = grit_repo.git.rev_list(@@opts, args)
    fixes = []
    Grit::Commit.list_from_string(grit_repo, commit_list).each do |commit|
      if commit.message =~ regex
        # TODO: what does this line do - ANSWER: search the tree to get blobs, not dirs
        commit.stats.files.map {|s| s.first}.select{ |s| tree/s }.each do |file|
          fixes << @@Fix.new(commit.date.to_s, commit.sha, file)
        end
      end
    end
    DB::add_events fixes, self.org, self.name, grit_repo.head.commit.sha
  end

  def get_hotspots(sha=nil)
    grit_repo = Grit::Repo.new self.dir
    tree = grit_repo.tree("master")
    files = Set.new
    if sha
      commit_list = grit_repo.git.rev_list(@@opts, sha, "^master")
      Grit::Commit.list_from_string(grit_repo, commit_list).each do |commit|
        files.add(commit.stats.files.map {|s| s.first}.select{ |s| tree/s })
      end
      hotspots = Hash.new(0)
      debugger
      files.each do |file|
        hotspots[file] = self.hotspots[file]
        puts file
      end
    else
      hotspots = self.hotspots
    end

    spots = hotspots.collect do |spot|
      @@Spot.new(spot.first, sprintf('%.4f', spot.last))
    end
    t = 1 - ((now - fix.date).to_f / (now - fixes.last.date))
    fix.files.each do |file|
      hotspots[file] += 1/(1+Math.exp((-12*t)+12))
    end
    debugger
    hotspots.sort_by {|k,v| v}.reverse!
    self.hotspots = hotspots
    return spots
  end
end