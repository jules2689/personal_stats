require "sqlite3"

class Database
  attr_accessor :db

  def self.format_time(t)
    t = case t
    when Time
      t
    when t =~ /\d+/
      Time.at(t.to_f)
    else
      Time.parse(t)
    end
    t.strftime("%Y-%m-%d %H:%M:%S")
  end

  def initialize
    @db = SQLite3::Database.new("messages.db")
    create_tables
  end

  def insert(table, values)
    cols = values.keys.join(',')
    q_marks = values.keys.map { |_| '?' }.join(',')
    @db.execute("INSERT OR IGNORE INTO #{table} (#{cols}) VALUES (#{q_marks})", values.values)
  end

  def slack_channels
    @db.execute("SELECT id, name from user_channels").to_h
  end

  def stats
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

  private

  def create_tables
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