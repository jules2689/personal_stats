require "bundler"
Bundler.setup(:default)

require 'dotenv/load'
require 'cli/ui'
require 'byebug'

require_relative 'slack_run'

SlackRun.run
