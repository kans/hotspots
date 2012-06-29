require 'google_chart'

module Helpers
  Stats = Struct.new(:hotspots, :danger_zone, :danger_percent, :danger_image)
  danger_images = [
    "",
  ]

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
    danger_image = danger_images[(e/danger_images.length).to_i]
    return Stats.new(hotspots, hottest_spots, hottest_spots.length/hotspots.length.to_f, danger_image)
  end

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

  def sort_hotspots(hotspots)
    hotspots.sort_by {|k, v| -v }
  end
end
