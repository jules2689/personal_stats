require 'slack-ruby-client'
require_relative '../database'
require_relative 'aggregator'
require_relative 'grapher'

Slack.configure do |config|
  config.token = ENV['SLACK_TOKEN']
end

module SlackStats
  class Run
    AFTER = "yesterday"
    CLIENT = Slack::Web::Client.new
    IGNORE_CHANNELS = %w(GFD2X1EPR)

    class << self
      def run
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
                database.insert_or_ignore('user_channels', id: message.channel.id, name: message.channel.name, type: 'group')
              end

              if message.channel.is_mpim
                database.insert_or_ignore('user_channels', id: message.channel.id, name: message.channel.name, type: 'mpim')
              end

              if message.channel.is_channel
                database.insert_or_ignore('user_channels', id: message.channel.id, name: message.channel.name, type: 'channel')
              end

              if message.channel.is_im
                user_info = CLIENT.users_info(user: message.channel.user)
                database.insert_or_ignore('user_channels', id: message.channel.user, name: user_info.user.real_name, type: 'user')
              end

              database.insert_or_ignore(
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
        scripts = []

        CLI::UI::Frame.open('Record and Send Stats') do
          stats = database.slack_stats

          CLI::UI::Frame.open('Record All Time Stats') do
            CLI::UI::Progress.progress do |bar|
              stats.each_with_index do |stat, idx|
                bar.tick(set_percent: (idx + 1) / stat.size.to_f)
                database.insert('stats', stat)
              end
              bar.tick(set_percent: 1.0)
            end

            stats = stats.max_by(5) { |s| s[:messages_sent] }.sort_by { |s| -s[:messages_sent] }
            scripts << Grapher.new("All Time").custom_graph(stacked: false) do
              values = stats.map.with_index do |s, i| 
                {
                  label: s[:name],
                  backgroundColor: Grapher.colors[i],
                  data: [s[:messages_sent]]
                }
              end
              [nil, values]
            end
          end

          scripts += Aggregator.new(database).run
          render_and_post_html(scripts)
        end
      end

      def render_and_post_html(scripts)
        SlackStats::DaySendCheck.with_check do
          # TODO: Clean up
          file_name = Time.now.to_s.gsub(/\s/, '_') + '.html'
          html = File.read(File.join(ROOT, 'html', 'page.html')).gsub(/{{ script }}/, scripts.join("\n"))
          File.write(File.join(ROOT, 'html', 'slacks', file_name), html)

          # Assumes the `server.py` is running in the html folder
          CLIENT.chat_postMessage(
            channel: '#personal-stats',
            text: "Rendered #{scripts.size} Graphs. Take a look! (http://localhost:8090/slacks/#{file_name})",
            username: "Julian's Stats",
            as_user: false,
            icon_emoji: ':learnding-ralph:'
          )
        end
      end
    end
  end
end
