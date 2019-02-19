require "bundler/inline"

gemfile do
  source 'https://rubygems.org'

  gem 'slack-ruby-client'
  gem 'dotenv'
  gem 'byebug'
  gem 'sqlite3'
  gem 'cli-ui'
end

require 'dotenv/load'
require 'cli/ui'
require 'byebug'

require_relative 'slack_stats/run'
require_relative 'geekbot/run'

ROOT = __dir__

CLI::UI::StdoutRouter.enable

CLI::UI::Frame.open('Slack Stats') do
  SlackStats::Run.run
end

CLI::UI::Frame.open('Geekbot Standups') do
  Geekbot::Run.run
end
