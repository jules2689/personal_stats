module SlackStats
  class DaySendCheck
    def initialize
      @days_sent_before = YAML.load_file(yaml_dir) rescue []
      @days_sent_before ||= []
    end

    def self.with_check(save: true)
      check = new
      check.with_check(save: save) { yield }
    end

    def with_check(save: true)
      if @days_sent_before.include?(today)
        return
        puts "Skipping"
      end
      yield
      @days_sent_before << today
      save! if save
      @days_sent_before
    end

    def save!
      File.write(yaml_dir, @days_sent_before.to_yaml) unless @days_sent_before.empty?
    end

    private

    def today
      @date ||= begin
        date = Date.today
        date.to_time.in_time_zone('America/New_York').beginning_of_day.to_s
      end
    end

    def yaml_dir
      File.join(__dir__, 'days_sent.yml')
    end
  end
end
