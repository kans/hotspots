require 'ostruct'
require 'uri'

require 'debugger'
require 'grit'
require 'github_api'

include FileUtils

class Repo < OpenStruct
  @@Spot = Struct.new(:file, :score)

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


  def set_hotspots()
    puts 'setting spots for ' + self.name
    regex = /fix(es|ed)?|close(s|d)?/i
    grit_repo = Grit::Repo.new self.dir
    tree = grit_repo.tree("master")

    opts = {:max_count => false, :no_merges => true, :pretty => "raw", :timeout => false}

    commit_list = grit_repo.git.rev_list(opts, 'master')
    
    id = $db.get_first_value "SELECT id FROM projects WHERE org=? and repo=?;", self.org, self.name 
    puts id
    query = "INSERT INTO events "
    args = []

    first_time = true
    Grit::Commit.list_from_string(grit_repo, commit_list).each do |commit|
      if commit.message =~ regex
        puts commit.message
        # TODO: what does this line do - ANSWER: search the tree to get blobs, not dirs
        commit.stats.files.map {|s| s.first}.select{ |s| tree/s }.each do |file|
          if first_time
            query << " SELECT ? AS 'project_id', ? AS 'sha', ? AS 'time', ? AS 'path' "
            first_time = false
          else
            query << " UNION SELECT ?, ?, ?, ? "
          end
          args += [id, commit.sha, commit.date.to_s, file]
          if args.length >900
            debugger;
            $db.execute query, args
            args=[]
            query = "INSERT INTO events "
            first_time = true
          end
        end
      end
    end
    debugger;
    unless args.empty?
      $db.execute query, args
    end
  end

  def get_hotspots(sha=nil)
    opts = {:max_count => false, :no_merges => true, :pretty => "raw", :timeout => false}
    grit_repo = Grit::Repo.new self.dir
    tree = grit_repo.tree("master")
    files = Set.new
    debugger
    if sha
      commit_list = grit_repo.git.rev_list(opts, sha, "^master")
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