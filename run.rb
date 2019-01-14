require "bundler"
Bundler.setup(:default)

require 'dotenv/load'
require 'cli/ui'
require 'byebug'

require_relative 'slack_stats/run'
require_relative 'geekbot/run'

CLI::UI::StdoutRouter.enable

CLI::UI::Frame.open('Slack Stats') do
  SlackStats::Run.run
end

CLI::UI::Frame.open('Geekbot Standups') do
  Geekbot::Run.run
end
