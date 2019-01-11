require "bundler"
Bundler.setup(:default)

require 'dotenv/load'
require 'slack-ruby-client'
require 'cli/ui'

require 'date'
require_relative 'database'

Slack.configure do |config|
  config.token = ENV['SLACK_TOKEN']
end

CLI::UI::StdoutRouter.enable

AFTER = "yesterday"
CLIENT = Slack::Web::Client.new
IGNORE_CHANNELS = %w(GFD2X1EPR)

def all_messages
  messages = []

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

  messages
end

database = Database.new

msgs = []
CLI::UI::Frame.open('Fetch Messages') do
  msgs = all_messages
end

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
        time_stamp: Time.at(message.ts.to_f).strftime("%Y-%m-%d %H:%M:%S")
      )
    end

    bar.tick(set_percent: 1.0)
  end
end

CLI::UI::Frame.open('Record and Send Stats') do
  stats = database.stats

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

  CLIENT.chat_postMessage(
    channel: '#personal-stats',
    text: messages_per_channel,
    username: "Julian's Stats",
    as_user: false,
    icon_emoji: ':learnding-ralph:'
  )
end
