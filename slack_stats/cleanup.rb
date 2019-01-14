require "bundler"
Bundler.setup(:default)

require 'dotenv/load'
require 'byebug'
require 'slack-ruby-client'

Slack.configure do |config|
  config.token = ENV['SLACK_TOKEN']
end

CLIENT = Slack::Web::Client.new
msgs = CLIENT.search_messages(query: "in:#personal-stats")
msgs.messages.matches.each { |m2|  CLIENT.chat_delete(ts: m2.ts, channel: m2.channel.id) rescue nil }
