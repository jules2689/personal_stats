require "bundler"
Bundler.setup(:default)

require 'dotenv/load'
require 'cli/ui'
require 'byebug'

require_relative 'slack_stats/run'

SlackStats::Run.run
