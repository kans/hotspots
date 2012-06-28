require 'json'

require 'sinatra'
require 'haml'
require 'google_chart'

require './repo'
require './db'

$settings = {}
repos = {}

configure do
  $settings = JSON.parse(File.read 'settings.json')
  settings_repos = $settings['repos']

  settings_repos.each do |repo|
    repo = Repo.new(repo)
    repos[repo.org] ||= {}
    repos[repo.org][repo.name] = repo
  end
  repos.each do |org, org_repos|
    org_repos.each do |name, repo|
      # repo.set_hooks
      # repo.add_events
    end
  end
end

helpers do
  Stats = Struct.new(:hotspots, :danger_zone, :danger_percent)

  def histogram(hotspots)
    hotspots = hotspots.dup
    spots = hotspots.map {|spot| spot.last}
    lc = GoogleChart::LineChart.new("500x500", "histogram", false)
    lc.data "Line green", spots, '00ff00'
    lc.axis :y, range:[0,1], font_size: 10, alignment: :center
    lc.show_legend = false
   # lc.shape_marker :circle, :color =&gt; '0000ff', :data_set_index =&gt; 0, :data_point_index =&gt; -1, :pixel_size =&gt; 10
    lc.to_url
  end

  def make_stats(hotspots, threshold)
    danger_total = 0
    threshold_total = 0
    hottest_spots = {}

    hotspots.each { |file, score| danger_total += score }
    hotspots.each do |file, score|
      hottest_spots[file] = score
      threshold_total += score
      break if threshold_total >= threshold * danger_total
    end
    return Stats.new(hotspots, hottest_spots, hottest_spots.length/hotspots.length.to_f)
  end
end

post "/api/:org/:name" do
  begin
    data = JSON.parse request.body.read
    action = data['action']
    unless action == 'opened'
      return
    end
    org = params[:org]
    name = params[:name]
    repo = repos[org][name]
    sha = data['head']['sha']
    puts sha
    hotspots = repo.get_hotspots_for_sha(sha: sha)
    puts hotspots
  rescue Exception => e
    puts e
  ensure
    status 204
  end
end


get "/hotspots/:org/:name/?:sha?" do |org, name, sha|
  @threshold = params[:threshold].to_f
  @total = 0
  @repo = repos[org][name]
  @spots = @repo.get_hotspots

  haml :hotspots
end


get '/' do
  haml :index, locals:{ :repos => repos }
end


get '/histogram' do 
  @repos = repos
  haml :histogram 
end
