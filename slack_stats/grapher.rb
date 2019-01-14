module SlackStats
  class Grapher
    def initialize(title, type_class = Gruff::StackedBar, by_name = false, *init_args)
      @by_name = by_name
      @graph = type_class.new(*init_args)
      @graph.theme = {
        :colors => [
          '#e6194b',
          '#3cb44b',
          '#ffe119',
          '#4363d8',
          '#f58231',
          '#911eb4',
          '#46f0f0',
          '#f032e6',
          '#bcf60c',
          '#fabebe',
          '#008080',
          '#e6beff',
          '#9a6324',
          '#fffac8',
          '#800000',
          '#aaffc3',
          '#808000',
          '#ffd8b1',
          '#000075',
          '#808080',
        ],
        :marker_color => 'black',
        :background_colors => %w(white white)
      }
      @graph.title = title
    end

    def graph(data, group_by, output_dir)
      if @by_name
        by_name_graph(data, group_by, output_dir)
      else
        default_graph(data, group_by, output_dir)
      end
    end

    private

    def by_name_graph(data, group_by, output_dir)
      data.each do |d|
        @graph.data (d['name'] || d[:name]), d[group_by]
      end
      @graph.write(output_dir)
    end

    def default_graph(data, group_by, output_dir)
      # Find the range of for dates and set those as the labels
      dates = data.group_by { |d| d['for_date'] }.keys.map { |d| Time.parse(d).to_i }
      labels = (dates.min..dates.max).step(60 * 60 * 24).to_a.map.with_index do |int_time, idx|
        [idx, Time.at(int_time).strftime("%m-%d")]
      end.to_h
      @graph.labels = labels

      if group_by.respond_to?(:call)
        group_by.call(@graph, labels.dup)
      else
        data.group_by { |d| d[group_by] }.each do |group, stats|
          stats = stats.map { |s| [ Time.parse(s['for_date']).strftime("%m-%d"), s['sum'] ] }.to_h
          values = labels.collect { |_, k| stats[k] || 0 }
          @graph.data group.to_sym, values
        end
      end

      @graph.write(output_dir)
    end
  end
end
