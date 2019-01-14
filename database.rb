require "sqlite3"

class Database
  attr_accessor :db

  def self.format_time(t)
    t = case t
    when Time
      t
    when Float
      Time.at(t)
    when t =~ /\d+/
      Time.at(t.to_f)
    else
      Time.parse(t)
    end
    t.strftime("%Y-%m-%d %H:%M:%S")
  end

  def initialize
    @db = SQLite3::Database.new("stats.db")
    create_slack_tables
    create_geekbot_tables
  end

  def insert(table, values)
    cols = values.keys.join(',')
    q_marks = values.keys.map { |_| '?' }.join(',')
    @db.execute("INSERT INTO #{table} (#{cols}) VALUES (#{q_marks})", values.values)
  end

  def insert_or_ignore(table, values)
    insert(table, values)
  rescue SQLite3::ConstraintException
    # Ignore the constraint
  end

  def select(table, keys, clause = nil, *args)
    @db.execute("SELECT #{keys.join(',')} from #{table} #{clause}", args).map { |entry| keys.zip(entry).to_h }
  end

  ## SLACK HELPERS

  def slack_channels
    @db.execute("SELECT id, name from user_channels").to_h
  end

  def slack_stats
    rows = @db.execute <<-SQL
    SELECT COUNT(link) AS count,
           channel_id,
         (SELECT name from user_channels WHERE id = channel_id OR id = user_id) as name
    FROM   messages
    GROUP  BY channel_id
    ORDER  BY count DESC
    SQL

    rows.map do |row|
      { channel_id: row[1], name: row[2], messages_sent: row[0] }
    end
  end

  def slack_aggregate_stats(group_by)
    since =  Database.format_time(Time.now.beginning_of_day - 60 * 60 * 24 * 10) # 10 days ago
    vals = (@db.execute <<-SQL, since)
      SELECT #{group_by}, sum(messages_sent), for_date from aggregate_stats
      WHERE channel_id != 'all' AND for_date > ?
      GROUP BY #{group_by}, for_date ORDER BY for_date, #{group_by} DESC;
    SQL
    vals.map { |entry| [group_by, 'sum', 'for_date'].zip(entry).to_h }
  end

  ## GEEKBOT HELPERS

  # TODO

  private

  def create_geekbot_tables
    @db.execute <<-SQL
      create table if not exists geekbot_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL UNIQUE,
        geekbot_report_id varchar(16),

        geekbot_standup_id varchar(16),
        standup varchar(128),

        user_id varchar(16),
        user varchar(128),
        user_avatar varchar(256),

        slack_ts varchar(48),
        time_stamp TIMESTAMP,

        channel varchar(128),

        recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
      );
    SQL

    @db.execute <<-SQL
      CREATE UNIQUE INDEX IF NOT EXISTS geekbot_report_id_user_id_index ON geekbot_reports (geekbot_report_id, user_id);
    SQL

    @db.execute <<-SQL
      CREATE INDEX IF NOT EXISTS geekbot_report_id_index ON geekbot_reports (geekbot_report_id);
    SQL

    @db.execute <<-SQL
      CREATE INDEX IF NOT EXISTS geekbot_standup_id_index ON geekbot_reports (geekbot_standup_id);
    SQL

    @db.execute <<-SQL
      CREATE INDEX IF NOT EXISTS user_id_index ON geekbot_reports (user_id);
    SQL

    @db.execute <<-SQL
      create table if not exists geekbot_report_answers (
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL UNIQUE,
        report_id varchar(16),

        geekbot_question_id varchar(16),
        question TEXT,

        geekbot_answer_id varchar(16),
        answer TEXT,

        geekbot_standup_id varchar(16),
        standup varchar(128),

        images TEXT,

        recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
        FOREIGN KEY(report_id) REFERENCES geekbot_report(id)
      );
    SQL

    @db.execute <<-SQL
      CREATE INDEX IF NOT EXISTS geekbot_question_id_index ON geekbot_report_answers (geekbot_question_id);
    SQL

    @db.execute <<-SQL
      CREATE UNIQUE INDEX IF NOT EXISTS geekbot_answer_id_index ON geekbot_report_answers (geekbot_answer_id);
    SQL
  end

  def create_slack_tables
    @db.execute <<-SQL
      create table if not exists messages (
        channel_id varchar(16),
        user_id varchar(16),
        type varchar(10),
        message TEXT,
        link varchar(128) PRIMARY KEY NOT NULL UNIQUE,
        time_stamp TIMESTAMP NOT NULL,
        recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
      );
    SQL

    @db.execute <<-SQL
      create table if not exists user_channels (
        id varchar(16) PRIMARY KEY NOT NULL UNIQUE,
        name varchar(128),
        type varchar(16)
      );
    SQL

    @db.execute <<-SQL
      create table if not exists stats (
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL UNIQUE,
        channel_id varchar(16),
        name varchar(128),
        messages_sent BIGINT,
        recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
      );
    SQL

    @db.execute <<-SQL
      create table if not exists aggregate_stats (
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL UNIQUE,
        channel_id varchar(16),
        type varchar(16),
        messages_sent BIGINT,
        for_date TIMESTAMP NOT NULL,
        recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
      );
    SQL

    @db.execute <<-SQL
      CREATE INDEX IF NOT EXISTS aggregate_stats_for_date_index ON aggregate_stats (for_date);
    SQL

    @db.execute <<-SQL
      CREATE UNIQUE INDEX IF NOT EXISTS aggregate_stats_channel_id_for_date_index ON aggregate_stats (channel_id, for_date);
    SQL
  end
end