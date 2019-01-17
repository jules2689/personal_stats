require 'gruff'
require 'yaml'
require 'date'

require_relative 'grapher'
require_relative 'graph_send_check'

module SlackStats
  class Aggregator
    def initialize(database, slack_client)
      @database = database
      @slack_client = slack_client
      @base_time = DateTime.now.prev_day.strftime("%Y/%m/%d")
    end

    def run
      CLI::UI::Frame.open('Record Aggregate Stats') do
        files_to_send = {}

        record_aggregates
        aggregate_by_channels(files_to_send)
        aggreate_by_type(files_to_send)
        send_to_slack(files_to_send)
      end
    end

    private

    def channels_map
      @channels_map ||= @database.slack_channels
    end

    def latest_for_date
      @latest_for_date ||= begin
        latest_date = @database.db.execute("SELECT for_date from aggregate_stats GROUP BY for_date ORDER BY for_date DESC LIMIT 1")

        # If latest_for_date is nil, then we start from the first date in stats
        if latest_date.empty?
          latest_date = @database.db.execute("SELECT time_stamp from messages GROUP BY time_stamp ORDER BY time_stamp ASC LIMIT 1")
        end

        latest_date.first.first
      end
    end

    def record_aggregates
      # TODO: CLI UI integration
      each_day(latest_for_date, DateTime.now).each do |range|
        beginning_date = Time.at(range).beginning_of_day
        end_date = Time.at(range).end_of_day
        next if end_date > Time.now # Dont record today's stats until its done
        puts "Covering from #{beginning_date} .. #{end_date}"

        # Find all messages between 2 times
        messages = @database.select(
          'messages',
          %w(channel_id user_id type),
          "WHERE time_stamp > ? AND time_stamp < ?",
          Database.format_time(beginning_date), Database.format_time(end_date)
        )

        # Overall Aggregation for the 'all' channel
        @database.insert_or_ignore('aggregate_stats', channel_id: 'all', messages_sent: messages.size, for_date: Database.format_time(beginning_date))

        # Per Channel Aggregation
        messages.group_by { |m| [m['channel_id'], m['user_id']] }.each do |key, channel_messages|
          @database.insert_or_ignore(
            'aggregate_stats',
            messages_sent: channel_messages.size,
            for_date: Database.format_time(beginning_date),
            channel_id: key[1] || key[0], # The first key may be nil, but may be the user id. Use that if we have it, fallback to channel ID
            type: channel_messages.first['type'] # The type will be reliable since the channel ID is involved
          )
        end
      end
    end

    def aggregate_by_channels(files_to_send)
      CLI::UI::Spinner.spin("Creating graphs per channel") do |spinner|
        dir = "#{__dir__}/graphs/channels/#{@base_time}"
        FileUtils.mkdir_p(dir)

        per_channel = @database.slack_aggregate_stats('channel_id')

        sent_per_channel = {}
        groups = per_channel.group_by { |c| c['channel_id'] }
        groups.each_with_index do |(channel_id, stats), idx|
          chan_name = channels_map[channel_id] || channel_id
          sent_per_channel[chan_name] = stats.map { |s| s['sum'] }.sum unless chan_name == 'all'
          spinner.update_title("[#{idx + 1}/#{groups.size}] Creating graph for #{chan_name}")
          Grapher.new(chan_name).graph(stats, ->(g, labels) do
            # Format the data a bit for ease of use
            stats = stats.map do |s|
              t =  Time.parse(s['for_date'])
              [ t.strftime("%m-%d"), { 'weekend' => t.saturday? || t.sunday?, 'sum' => s['sum'] } ]
            end.to_h

            # We need to add stats based on the weekend to differentiate weekend days
            messages = labels.map do |_, k|
              next 0 unless stats[k]
              stats[k]['weekend'] ? 0 : stats[k]['sum']
            end
            g.data :Messages, messages

            weekend_messages = labels.collect do |_, k|
              next 0 unless stats[k]
              stats[k]['weekend'] ? stats[k]['sum'] : 0
            end
            g.data :'Weekend Messages', weekend_messages
          end, "#{dir}/#{chan_name}.png")
        end

        # Send graphs for only the top 5 channels / users
        sent_per_channel.sort_by { |_, v| -v }.take(5).each do |chan, _|
           files_to_send["Per Channel: #{chan}"] = "#{dir}/#{chan}.png"
        end
        spinner.update_title "Done creating graphs per channel"
      end
    end

    def aggreate_by_type(files_to_send)
      CLI::UI::Spinner.spin("Creating stacked graph for types") do |spinner|
        dir = "#{__dir__}/graphs/types/#{@base_time}"
        FileUtils.mkdir_p(dir)

        per_type = @database.slack_aggregate_stats('type')
        Grapher.new("Messages sent per Type").graph(per_type, 'type', "#{dir}/graph.png")
        files_to_send["Per Type Stats"] = "#{dir}/graph.png"
      end
    end

    def send_to_slack(files_to_send)
      CLI::UI::Spinner.spin("Sending files to slack") do |spinner|
        graphs_sent = 0
        files_sent_before = []
        send_check = SlackStats::GraphSendCheck.new

        files_to_send.each do |title, path|
          files_sent_before = send_check.with_check(path: path, save: false) do
            graphs_sent += 1
            spinner.update_title "Sending #{__dir__, '.../')}"
            @slack_client.files_upload(
              channels: '#personal-stats',
              file: Faraday::UploadIO.new(path, 'image/png'),
              title: title,
              filename: 'graph.jpg',
              initial_comment: "*Graph:* #{title}\n*Date:* #{@base_time}"
            )
          end
        end

        # Notify of the files sent as files cannot be sent with `as_user: false` so I wont get notified
        if graphs_sent > 0
          send_check.save!
          @slack_client.chat_postMessage(
            channel: '#personal-stats',
            text: "Sent #{graphs_sent} Graphs. Take a look!",
            username: "Julian's Stats",
            as_user: false,
            icon_emoji: ':learnding-ralph:'
          )
        end
      end
    end

    def each_day(start_date, end_date)
      start_date = case start_date
      when DateTime, Time, Float
        start_date.to_i
      when start_date =~ /\d+/
        start_date.to_i
      else
        Time.parse(start_date).to_i
      end

      end_date = case end_date
      when DateTime, Time, Float
        end_date.to_i
      when end_date =~ /\d+/
        end_date.to_i
      else
        Time.parse(end_date).to_i
      end

      (start_date.to_i..end_date.to_i).step(60 * 60 * 24)
    end

  end
end
