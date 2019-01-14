require 'slack-ruby-client'
require_relative '../database'
require_relative 'aggregator'

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
          # TODO: Is this useful with aggregates involved?
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

          Aggregator.new(database, CLIENT).run
        end

      end
    end
  end
end
