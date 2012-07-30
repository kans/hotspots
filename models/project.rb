require 'uri'

require 'debugger'
require 'grit'
require 'github_api'

require 'sequel'
require './helpers'

include FileUtils

$DB.create_table? :projects do
  primary_key :id
  String :access_token
  String :org, null: false
  String :name, null: false
  String :last_sha
  unique [:org, :name]
end

class Project < Sequel::Model
  @@Fix = Struct.new(:project_id, :date, :sha, :file)
  @@opts = {:max_count => false, :no_merges => true, :pretty => "raw", :timeout => false}

  attr_accessor :hotspots, :org, :name

  def full_name()
    return "#{@org}/#{@name}"
  end

  def initialize(project)
    project.each do |k, v|
      self.instance_variable_set("@#{k.to_s}", v)
    end
    @hotspots = Hash.new(0)
    @dir = File.expand_path("#{$settings['project_dir']}/#{@org}/#{@name}")
    debugger
    mkdir_p(@dir, mode: 0755)
    @grit_git = Grit::Git.new @dir

    @login = $settings['login']
    @password = CGI::escape $settings['password']
    process = @grit_git.clone({progress: true, process_info: true, timeout: 30},
      "https://#{@login}:#{@password}@github.com/#{@org}/#{@name}", @dir)
    print process[2]
    mkdir_p(@dir, mode: 0755)
    @grit_repo = Grit::Repo.new @dir
    self.pull()
  end

  def pull()
    puts "Pulling #{self.full_name}, #{@dir}"
    process = @grit_repo.git.pull({progress: true, process_info: true, timeout: 30, chdir: @dir}, "origin", "master")
    print process.slice(1,2)
  end

  def set_hooks()
    puts "Setting hooks for #{self.full_name}"
    hook_url = URI.join $settings['address'], "/api/#{@org}/#{@name}"

    github = Github.new basic_auth: "#{self.login}:#{@password}"
    options = {per_page: 100}
    hooks = github.repos.hooks.all(@org, @name, options.dup)
    hooks_to_delete = []
    hooks.each do |hook|
      if hook.name == "web" and hook.config.url == hook_url.to_s then
        puts "Deleting hook #{hook}"
        hooks_to_delete.push(hook)
      end
    end
    hooks_to_delete.each do |hook|
      github.repos.hooks.delete @org, @name, hook.id
    end
    github.repos.hooks.create @org, @name, name: "web", active: true,
      events: ["pull_request"], config: {url: hook_url, content_type: "json"}
  end

  def comment(pr_id, comment)
    github = Github.new basic_auth: "#{self.login}:#{@password}"
    github.issues.comments.create @org, @name, pr_id, {body: comment}
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
    puts 'setting spots for ' + @name
    last_sha = $DB[:projects].where(id: project_id).get(:last_sha)
    args = []
    if last_sha
      args << "^#{last_sha}"
    end
    args << 'master'
    commit_list = @grit_repo.git.rev_list @@opts.dup, args
    fixes = self.get_fixes_from_commits commit_list

    DB::add_events fixes, @grit_repo.head.commit.sha, self.id
  end

  def get_hotspots()
    hotspots = Hash.new 0
    now = Time.now
    events = DB::get_events self.id
    return [] if events.empty?
    denom = now - Time.parse(events.last.date)
    max = 0
    events.each do |event|
      t = 1 - ((now - Time.parse(event.date)).to_f / denom )
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
