require_relative 'api'
require_relative '../database'

module Geekbot
  class Run
    def self.run
      database = Database.new
      record_new_instances(database)
    end

    def self.record_new_instances(database)
      CLI::UI::Spinner.spin('Recording standups') do |spinner|
        standups = Geekbot::API.standups
        standups.each_with_index do |standup, idx|
          spinner.update_title "[#{idx + 1}/#{standups.size}] #{standup['id']} => #{standup['name']}"

          # Only need it since the latest report
          latest_report = database.select(
            'geekbot_reports',
            %w(time_stamp),
            "WHERE geekbot_standup_id='#{standup['id']}' ORDER BY id ASC LIMIT 1"
          ).first
          latest_report = Time.parse(latest_report['time_stamp']).to_i.to_s if latest_report

          # Record all questions
          reports = Geekbot::API.reports(standup['id'], latest_report)
          reports.each_with_index do |report, idx2|
            spinner.update_title "[#{idx + 1}/#{standups.size}] #{standup['id']} => #{standup['name']} => Report [#{idx2 + 1}/#{reports.size}]"
            record_questions(database, standup, report)
          end
        end

        spinner.update_title "Finished recording standups"
      end
    end

    def self.record_questions(database, standup, report)
      id = insert(database, standup, report)
      return unless id
      report['questions'].each do |question|
        database.insert_or_ignore(
          'geekbot_report_answers',
          report_id: id,
          geekbot_question_id: question['question_id'],
          question: question['question'],
          geekbot_answer_id: question['id'],
          answer: question['answer'],
          geekbot_standup_id: report['standup_id'],
          standup: standup['name'],
          images: question['images'].to_json
        )
      end
    end

    def self.insert(database, standup, report)
      database.insert(
        'geekbot_reports',
        geekbot_report_id: report['id'],
        geekbot_standup_id: report['standup_id'],
        standup: standup['name'],

        user_id: report['member']['id'],
        user: report['member']['realname'],
        user_avatar: report['member']['profileImg'],

        slack_ts: report['slack_ts'],
        time_stamp: Database.format_time(report['timestamp']),
        channel: report['channel'],
      )
      database.select('geekbot_reports', %w(id), "WHERE geekbot_report_id='#{report['id']}'").first['id']
    rescue SQLite3::ConstraintException
      database.select('geekbot_reports', %w(id), "WHERE geekbot_report_id='#{report['id']}'").first['id']
    end
  end
end
