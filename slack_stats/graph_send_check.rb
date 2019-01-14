module SlackStats
  class GraphSendCheck
    def self.with_check(path:, save: true)
      files_sent_before = YAML.load_file(yaml_dir) rescue []
      if files_sent_before.include?(path)
        return
        puts "Skipping #{path}"
      end
      yield
      files_sent_before << path
      save(files_sent_before) if save
      files_sent_before
    end

    def self.yaml_dir
      File.join(__dir__, 'graphs_sent.yml')
    end

    def self.save(files_sent_before)
      File.write(yaml_dir, files_sent_before.to_yaml) unless files_sent_before.empty?
    end
  end
end
