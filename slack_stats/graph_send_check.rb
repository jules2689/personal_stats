module SlackStats
  class GraphSendCheck
    def initialize
      @files_sent_before = YAML.load_file(yaml_dir) rescue []
    end

    def with_check(path:, save: true)
      if @files_sent_before.include?(path)
        return
        puts "Skipping #{path}"
      end
      yield
      @files_sent_before << path
      save! if save
      @files_sent_before
    end

    def save!
      File.write(yaml_dir, @files_sent_before.to_yaml) unless @files_sent_before.empty?
    end

    private

    def yaml_dir
      File.join(__dir__, 'graphs_sent.yml')
    end
  end
end
