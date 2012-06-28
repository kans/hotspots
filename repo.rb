require 'ostruct'
require 'uri'

require 'debugger'
require 'grit'
require 'github_api'
require './db'

include FileUtils

class Repo < OpenStruct
  @@Spot = Struct.new(:file, :score)
  @@Fix = Struct.new(:project_id, :date, :sha, :file)
  @@opts = {:max_count => false, :no_merges => true, :pretty => "raw", :timeout => false}

  def full_name()
    return "#{self.org}/#{self.name}"
  end

  def initialize(repo)
    super(repo)
    self.hotspots = Hash.new(0)
    self.dir = File.expand_path("#{$settings['repo_dir']}/#{self.org}/#{self.name}")
    mkdir_p(self.dir, mode: 0755)
    self.grit_git = Grit::Git.new self.dir

    password = CGI::escape self.password
    process = self.grit_git.clone({progress: true, process_info: true, timeout: 30},
      "https://#{self.login}:#{password}@github.com/#{self.org}/#{self.name}", self.dir)
    print process[2]
    self.grit_repo = Grit::Repo.new self.dir
    self.pull()
    self.id = DB::create_project self
  end

  def pull
    process = self.grit_repo.git.pull({progress: true, process_info: true}, self.dir)
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

  def get_fixes_from_commits(commit_list)
    fixes = []
    regex = /fix(es|ed)?|close(s|d)?/i
    tree = self.grit_repo.tree("master")
    Grit::Commit.list_from_string(self.grit_repo, commit_list).each do |commit|
      if commit.message =~ regex
        # TODO: what does this line do - ANSWER: search the tree to get blobs, not dirs
        commit.stats.files.map {|s| s.first}.select{ |s| tree/s }.each do |file|
          fixes << @@Fix.new(self.id, commit.date.to_s, commit.sha, file)
        end
      end
    end
    return fixes
  end

  def add_events
    puts 'setting spots for ' + self.name
    last_sha = DB::get_last_sha self.id
    args = []
    if last_sha
      args << "^#{last_sha}"
    end
    args << 'master'
    commit_list = self.grit_repo.git.rev_list @@opts.dup, args
    fixes = self.get_fixes_from_commits commit_list
    
    DB::add_events fixes, self.grit_repo.head.commit.sha, self.id
  end

  def get_hotspots
    hotspots = Hash.new 0
    now = Time.now
    events = DB::get_events self.id
    events.each do |event|
      t = 1 - ((now - Time.parse(event.date)).to_f / (now - Time.parse(events.last.date)))
      hotspots[event.file] += 1/(1+Math.exp((-12*t)+12))
    end
    return hotspots
  end

  def get_hotspots_for_sha(sha)
    files = Set.new

    commit_list = self.grit_repo.git.rev_list(@@opts.dup, sha, "^master")
    fixes = self.get_fixes_from_commits commit_list
    hotspots = Hash.new(0)
    debugger
    files.each do |file|
      hotspots[file] = self.hotspots[file]
      puts file
    end

    spots = hotspots.collect do |spot|
      @@Spot.new(spot.first, sprintf('%.4f', spot.last))
    end
    t = 1 - ((now - fix.date).to_f / (now - fixes.last.date))
    fix.files.each do |file|
      hotspots[file] += 1/(1+Math.exp((-12*t)+12))
    end
    debugger
    hotspots.sort_by! {|k,v| v}.reverse!
    self.hotspots = hotspots
    return spots
  end
end