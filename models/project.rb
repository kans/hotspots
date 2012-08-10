require 'uri'

require 'debugger'
require 'grit'
require 'github_api'

require 'sequel'
require './helpers'

include FileUtils


class Project < Sequel::Model

  one_to_many :events
  plugin :schema
  set_schema do
    primary_key :id
    String :access_token
    String :org, null: false
    String :name, null: false
    # TODO: remove me?
    String :last_sha
    unique [:org, :name]
  end

  @@Fix = Struct.new(:project_id, :date, :sha, :file)
  @@opts = {:max_count => false, :no_merges => true, :pretty => "raw", :timeout => false}

  attr_accessor :hotspots

  def uninstall
    self.delete_hook
    is_org = true
    begin
      org = self.Github.orgs.get self.org
    rescue Github::Error::GithubError => e
      is_org = false if e.is_a? Github::Error::NotFound
    end

    unless is_org
      self.Github.repos.collaborators.remove self.org, self.name, $settings['login']
    else
      teams = self.Github.orgs.teams.all self.org
      remove_access = []
      teams.each do |team|
        remove_access << team if team['name'] == $settings["team_name"]
      end
      remove_access.each do |team|
        conn = Faraday.new(:url => 'https://api.github.com')
        response = conn.delete("/teams/#{team['id']}/repos/#{self.org}/#{self.name}", 
          {:access_token => self.access_token })
      end
    end
    self.delete
  end

  def full_name()
    return "#{self.org}/#{self.name}"
  end

  def initialize(full_name, token)
    org, name = full_name.split("/")
    super(org: org, name: name, access_token: token)
    self.init_git()
  end

  def init_git()
    @hotspots ||= Hash.new(0)
    @dir = File.expand_path("#{$settings['project_dir']}/#{self.org}/#{self.name}")
    mkdir_p(@dir, mode: 0755)
    @grit_git = Grit::Git.new @dir

    @login = $settings['login']
    @password = CGI::escape $settings['password']
    # TODO: use clone_url and token
    process = @grit_git.clone({progress: true, process_info: true, timeout: 30},
      "https://#{@login}:#{@password}@github.com/#{self.org}/#{self.name}", @dir)
    print process[2]
    mkdir_p(@dir, mode: 0755)
    @grit_repo = Grit::Repo.new @dir
    self.pull()
  end

  def pull()
    #puts "Pulling #{self.full_name}, #{@dir}"
    process = @grit_repo.git.pull({progress: true, process_info: true, timeout: 30, chdir: @dir}, "origin", "master")
    print process.slice(1,2)
  end

  def Github()
    access_token = self.access_token
    return Github.new do |config|
      config.oauth_token = access_token
      config.adapter = :em_synchrony
    end
  end

  def get_hook_url()
    URI.join $settings['address'], "/api/#{self.org}/#{self.name}"
  end

  def get_hooks()
    self.Github.repos.hooks.all(self.org, self.name, {per_page: 100})
  end

  def create_hook()
    self.Github.repos.hooks.create self.org, self.name, name: "web", active: true,
      events: ["pull_request"], config: {url: self.get_hook_url, content_type: "json"}
  end

  def set_hooks()
    puts "Setting hooks for #{self.full_name}"
    self.delete_hook
    self.create_hook
  end

  def delete_hook()
    to_delete = []
    self.get_hooks.each do |hook|
      if hook.name == "web" && hook.config.url == self.get_hook_url.to_s
        to_delete << hook.id
      end
    end
    to_delete.each {|id| self.Github.repos.hooks.delete self.org, self.name, id }
  end

  def comment(pr_id, comment)
    github = Github.new do |config|
      config.basic_auth = "#{self.login}:#{@password}"
      config.adapter = :em_synchrony
    end
    github.issues.comments.create self.org, self.name, pr_id, {body: comment}
  end

  def get_fixes_from_commits(commit_list)
    fixes = []
    regex = /fix(es|ed)?|close(s|d)?/i
    tree = @grit_repo.tree("master")
    Grit::Commit.list_from_string(@grit_repo, commit_list).each do |commit|
      if commit.message =~ regex
        # TODO: what does this line do - ANSWER: search the tree to get blobs, not dirs
        commit.stats.files.map {|s| s.first}.select{ |s| tree/s }.each do |file|
          fixes << @@Fix.new(self.id, commit.date.to_s, commit.sha, file)
        end
      end
    end
    return fixes
  end

  def add_events()
    puts 'setting spots for ' + self.name
    args = []
    if self.last_sha
      args << "^#{self.last_sha}"
    end
    args << 'master'
    commit_list = @grit_repo.git.rev_list @@opts.dup, args
    fixes = self.get_fixes_from_commits commit_list

    # TODO: this is super slow and sucky
    fixes.each do |fix|
      begin
        self.add_event date: fix.date, sha: fix.sha, file: fix.file
      rescue
        # TODO: Fix
      end
    end
    self.last_sha = @grit_repo.head.commit.sha
    self.save
  end

  def get_hotspots()
    hotspots = Hash.new 0
    now = Time.now
    events = self.events.dup
    events.sort! { |a,b| b.date.to_i <=> a.date.to_i }
    return [] if events.empty?
    denom = now - events.last.date
    max = 0
    events.each do |event|
      t = 1 - ((now - event.date).to_f / denom )
      hotspots[event.file] += 1/(1+Math.exp((-12*t)+12))
      max = [hotspots[event.file], max].max
    end
    hotspots.each_pair do |k, v|
      hotspots[k] = v / max
    end

    return hotspots
  end

  def get_hotspots_for_sha(from_sha, to_sha=nil)
    spots = self.get_hotspots
    files = self.get_files(from_sha, to_sha)
    filtered_spots = self.filter_hotspots(spots, files)
    return Helpers::sort_hotspots(filtered_spots)
  end

  def filter_hotspots(hotspots, files)
    filtered_spots = Hash.new
    files.each do |file|
      filtered_spots[file] = (hotspots.has_key?(file) ? hotspots[file] : 0.0)
    end
    return filtered_spots
  end

  def get_files(from_sha, to_sha)
    files = Set.new
    to_sha ||= "master"

    self.pull() # TODO: remove this line
    commit_list = @grit_repo.git.rev_list(@@opts.dup, from_sha, "^"+to_sha)
    tree = @grit_repo.tree(to_sha || from_sha || "master")
    Grit::Commit.list_from_string(@grit_repo, commit_list).each do |commit|
      # TODO: what does this line do - ANSWER: search the tree to get blobs, not dirs
      commit.stats.files.map {|s| s.first}.select{ |s| tree/s }.each do |file|
        files.add(file)
      end
    end
    return files
  end
end
