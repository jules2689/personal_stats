require "bundler"
Bundler.setup(:default)

require 'dotenv/load'
require 'byebug'
require 'slack-ruby-client'
require 'cli/ui'

Slack.configure do |config|
  config.token = ENV['SLACK_TOKEN']
end

CLIENT = Slack::Web::Client.new

CLI::UI::StdoutRouter.enable

def all_messages
  messages = []

  CLI::UI::Frame.open('Fetch Messages') do
    CLI::UI::Spinner.spin('Fetching messages from personal-stats') do |spinner|
      response = CLIENT.search_messages(query: "in:#personal-stats", sort: 'timestamp')
      total = response.messages.paging.total
      messages += response.messages.matches

      puts "Have #{response.messages.paging.pages - 1} more pages to fetch"
      pages = (2..response.messages.paging.pages)

      pages.each do |page|
        spinner.update_title("Fetching #{page} of #{response.messages.paging.pages}")
        retries = 0
        begin
          response = CLIENT.search_messages(query: "in:#personal-stats", sort: 'timestamp', page: page)
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

      spinner.update_title "Total sent: #{total}"
    end
  end

  messages
end

all_messages.each { |m2|  CLIENT.chat_delete(ts: m2.ts, channel: m2.channel.id) rescue nil }
