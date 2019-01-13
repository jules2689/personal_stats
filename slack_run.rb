require 'slack-ruby-client'
require 'gruff'

require 'date'
require_relative 'database'

Slack.configure do |config|
  config.token = ENV['SLACK_TOKEN']
end

class SlackRun
  AFTER = "yesterday"
  CLIENT = Slack::Web::Client.new
  IGNORE_CHANNELS = %w(GFD2X1EPR)

  class << self
    def run
      CLI::UI::StdoutRouter.enable

      database = Database.new
      msgs = all_messages

      record_messages(database, msgs)
      record_stats(database)
    end

    private

    def all_messages
      messages = []

      CLI::UI::Frame.open('Fetch Messages') do
        CLI::UI::Spinner.spin('Fetching messages from Slack since ' + AFTER) do |spinner|
          response = CLIENT.search_messages(query: "from:@julian after:#{AFTER}", sort: 'timestamp')
          total = response.messages.paging.total
          messages += response.messages.matches

          puts "Have #{response.messages.paging.pages - 1} more pages to fetch"
          pages = (2..response.messages.paging.pages)

          pages.each do |page|
            spinner.update_title("Fetching #{page} of #{response.messages.paging.pages}")
            retries = 0
            begin
              response = CLIENT.search_messages(query: "from:@julian after:#{AFTER}", sort: 'timestamp', page: page)
              messages += response.messages.matches
            rescue Slack::Web::Api::Errors::TooManyRequestsError => e
              if retries > 3
                raise e
              else
                time = e.message.match(/Retry after (\d+)/i)
                time = time ? time[1].to_i : 10
                spinner.update_title "Sleeping due to Slack Timeout for #{time}s"
                sleep time
                retry
              end
            end
          end

          spinner.update_title "Total sent since yesterday: #{total}"
        end
      end

      messages
    end

    def record_messages(database, msgs)
      CLI::UI::Frame.open('Record Messages') do
        puts "Recording up to #{msgs.size} messages"
        CLI::UI::Progress.progress do |bar|
          msgs.each_with_index do |message, idx|
            bar.tick(set_percent: (idx.to_f / msgs.size))
            next if IGNORE_CHANNELS.include?(message.channel.id)

            if message.channel.is_group && !message.channel.is_mpim
              database.insert('user_channels', id: message.channel.id, name: message.channel.name, type: 'group')
            end

            if message.channel.is_mpim
              database.insert('user_channels', id: message.channel.id, name: message.channel.name, type: 'mpim')
            end

            if message.channel.is_channel
              database.insert('user_channels', id: message.channel.id, name: message.channel.name, type: 'channel')
            end

            if message.channel.is_im
              user_info = CLIENT.users_info(user: message.channel.user)
              database.insert('user_channels', id: message.channel.user, name: user_info.user.real_name, type: 'user')
            end

            database.insert(
              'messages',
              channel_id: message.channel.id,
              user_id: message.channel.user,
              type: message.type,
              message: message.text,
              link: message.permalink,
              time_stamp: Database.format_time(message.ts.to_f)
            )
          end

          bar.tick(set_percent: 1.0)
        end
      end
    end

    def record_stats(database)
      CLI::UI::Frame.open('Record and Send Stats') do
        stats = database.stats

        CLI::UI::Frame.open('Record All Time Stats') do
          CLI::UI::Progress.progress do |bar|
            stats.each_with_index do |stat, idx|
              bar.tick(set_percent: (idx + 1) / stat.size.to_f)
              database.insert('stats', stat)
            end
            bar.tick(set_percent: 1.0)
          end

          messages_per_channel = "*Top 10 Of All Time:*\n" + stats.take(10).map do |stat|
            msg = "#{stat[:name]}: #{stat[:messages_sent]}"
          end.join("\n")

          # CLIENT.chat_postMessage(
          #   channel: '#personal-stats',
          #   text: messages_per_channel,
          #   username: "Julian's Stats",
          #   as_user: false,
          #   icon_emoji: ':learnding-ralph:'
          # )
        end

        aggregate_stats(database)
      end

    end

    def aggregate_stats(database)
      CLI::UI::Frame.open('Record Aggregate Stats') do
        latest_for_date = begin
          latest_date = database.db.execute("SELECT for_date from aggregate_stats GROUP BY for_date ORDER BY for_date DESC LIMIT 1")

          # If latest_for_date is nil, then we start from the first date in stats
          if latest_date.empty?
            latest_date = database.db.execute("SELECT time_stamp from messages GROUP BY time_stamp ORDER BY time_stamp ASC LIMIT 1")
          end

          latest_date.first.first
        end

        # Record new stats
        range_to_cover = (DateTime.parse(latest_for_date).to_i..DateTime.now.to_i).step(60 * 60 * 24)
        range_to_cover.each do |range|
          beginning_date = Time.at(range).beginning_of_day
          end_date = Time.at(range).end_of_day
          next if end_date > Time.now
          puts "Covering from #{beginning_date} .. #{end_date}"

          messages = database.db.execute("SELECT * from messages WHERE time_stamp > ? AND time_stamp < ?", Database.format_time(beginning_date), Database.format_time(end_date))

          # Overall
          database.insert('aggregate_stats', channel_id: 'all', messages_sent: messages.size, for_date: Database.format_time(beginning_date))

          # Per Channel
          messages.group_by { |m| [m[0], m[1]] }.each do |key, channel_messages|
            database.insert(
              'aggregate_stats',
              messages_sent: channel_messages.size,
              for_date: Database.format_time(beginning_date),
              channel_id: key[1] || key[0],
              type: channel_messages.first[2]
            )
          end
        end

        channels = database.slack_channels
        since =  Database.format_time(Time.now.beginning_of_day - 60 * 60 * 24 * 10)
        files_to_send = {}

        CLI::UI::Spinner.spin("Creating graphs per channel") do |spinner|
          dir = "graphs/channels/#{Time.now.strftime("%Y/%m/%d")}"
          FileUtils.mkdir_p(dir)

          per_channel = database.db.execute <<-SQL, since
            SELECT channel_id, sum(messages_sent) as total_sent, for_date from aggregate_stats
            WHERE for_date > ?
            GROUP BY channel_id, for_date ORDER BY for_date, channel_id DESC;
          SQL

          sent_per_channel = {}
          groups = per_channel.group_by(&:first)
          groups.each_with_index do |(channel_id, stats), idx|
            chan_name = channels[channel_id] || channel_id
            # spinner.update_title("[#{idx + 1}/#{groups.size}] Creating graph for #{chan_name}")
            g = Gruff::StackedBar.new
            g.theme = {
              :colors => %w(orange purple),
              :marker_color => 'black',
              :background_colors => %w(white white)
            }

            g.title = "Per Channel: #{chan_name}"
            g.labels = stats.group_by(&:last).keys.map.with_index { |k, idx| [idx, Time.parse(k).strftime("%m-%d")] }.to_h
            g.data :Messages, stats.collect { |s| t = Time.parse(s[2]); t.saturday? || t.sunday? ? 0 : s[1] }
            g.data :'Weekend Messages', stats.collect { |s| t = Time.parse(s[2]); t.saturday? || t.sunday? ? s[1] : 0 }
            g.write("#{dir}/#{chan_name}.png")
            sent_per_channel[chan_name] = stats.map { |s| s[1] }.sum unless chan_name == 'all'
          end

          files_to_send["Per Type Stats"] = "#{dir}/all.png"
          sent_per_channel.sort_by { |_, v| -v }.take(5).each do |chan, _|
             files_to_send["Per Channel: #{chan}"] = "#{dir}/#{chan}.png"
          end 
          spinner.update_title "Done creating graphs per channel"
        end

        CLI::UI::Spinner.spin("Creating stacked graph for types") do |spinner|
          dir = "graphs/types/#{Time.now.strftime("%Y/%m/%d")}"
          FileUtils.mkdir_p(dir)

          per_type = database.db.execute <<-SQL, since
            SELECT type, sum(messages_sent), for_date from aggregate_stats
            WHERE channel_id != 'all' AND for_date > ?
            GROUP BY type, for_date ORDER BY for_date, type DESC;
          SQL

          g = Gruff::StackedBar.new
          g.theme = {
            :colors => %w(orange purple blue yellow),
            :marker_color => 'black',
            :background_colors => %w(white white)
          }
          g.title = "Messages sent per Type"

          labels = per_type.group_by(&:last).keys.map.with_index { |k, idx| [idx, Time.parse(k).strftime("%m-%d")] }.to_h
          g.labels = labels
          per_type.group_by(&:first).each do |type, stats|
            stats = stats.map { |s| [ Time.parse(s[2]).strftime("%m-%d"), s[1]] }.to_h
            values = labels.map { |_, k| stats[k] || 0 }
            g.data type.to_sym, values
          end

          g.write("#{dir}/graph.png")
          files_to_send["Per Type Stats"] = "#{dir}/graph.png"
        end

        files_to_send.each do |title, path|
          CLIENT.files_upload(
            channels: '#personal-stats',
            as_user: true,
            file: Faraday::UploadIO.new(path, 'image/png'),
            title: title,
            filename: 'graph.jpg',
            initial_comment: "#{title} since #{since}"
          )
        end
      end
    end
  end
end
