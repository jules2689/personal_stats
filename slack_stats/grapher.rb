require 'time'
require 'json'

module SlackStats
  class Grapher
    def initialize(title)
      @title = title
    end

    def graph(data, group_by)
      values = if group_by.is_a?(Proc)
        group_by.call(labels)
      else
        default_graph(data, group_by)
      end
      data = { labels: labels, datasets: values }.to_json
      script(data, true)
    end

    def custom_graph(stacked: true)
      labels, values = yield
      data = { datasets: values }
      data[:labels] = labels if labels
      script(data.to_json, stacked)
    end

    def self.colors
      [
        'rgb(255, 99, 132)',  # red
        'rgb(75, 192, 192)',  # green
        'rgb(153, 102, 255)', # purple
        'rgb(255, 159, 64)',  # orange
        'rgb(255, 205, 86)',  # yellow
        'rgb(54, 162, 235)',  # blue
        'rgb(201, 203, 207)'  # grey
      ]
    end

    private

    def script(data, stacked)
      scale = stacked ? " window.stacked_scale" : "{}"
      var = ('a'..'z').to_a.shuffle[0,8].join
      <<~EOF
      var data_#{var} = #{data};
      graph("#{@title.encode("UTF-8")}", data_#{var}, #{scale});
      EOF
    end

    def labels
      @labels ||= begin
        # Find the range of for dates and set those as the labels
        max_date = DateTime.now.prev_day # Start from yesterday so we have a full day's data
        min_date = max_date.prev_day(7) # Always want the last 7 days
        (min_date.to_time.to_i..max_date.to_time.to_i).step(60 * 60 * 24).to_a.map do |int_time|
          Time.at(int_time).strftime("%m-%d")
        end
      end
    end

    def default_graph(data, group_by)
      data.group_by { |d| d[group_by] }.map.with_index do |(group, stats), idx|
        stats = stats.map { |s| [ Time.parse(s['for_date']).strftime("%m-%d"), s['sum'] ] }.to_h
        {
          label: group,
          backgroundColor: Grapher.colors[idx],
          data: labels.collect { |k| stats[k] || 0 }
        }
      end
    end
  end
end
