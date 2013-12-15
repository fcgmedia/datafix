require "datafixes"
require "datafix/version"
require "datafix/railtie" if defined?(Rails)

class Datafix
  class << self
    DIRECTIONS = %w[up down]

    def migrate(direction)
      raise ArgumentError unless DIRECTIONS.include?(direction)

      ActiveRecord::Base.transaction do
        send(direction.to_sym)
        log_run(direction)
      end
    end

    private
    def migration_name
      @migration_name ||= self.name.camelize.split('::').tap(&:shift).join('::')
    end

    def log_run(direction)
      puts "migrating #{migration_name} #{direction}"

      execute(<<-SQL)
      INSERT INTO datafix_log
      (direction, script, timestamp)
      VALUES ('#{direction}', '#{migration_name.camelize}', NOW())
      SQL
    end

    def connection
      @connection ||= ActiveRecord::Base.connection
    end

    def execute(*args)
      connection.execute(*args)
    end

    def table_exists?(table_name)
      ActiveRecord::Base.connection.table_exists? table_name
    end

    def archive_table(table_name)
      new_table_name = [table_name, "datafix", migration_name].join("_").downcase
      log "Archive #{table_name} for Rollback" if self.respond_to?(:log)
      execute("CREATE TABLE archived_#{new_table_name} LIKE #{table_name}")
      execute "INSERT INTO archived_#{new_table_name} SELECT * FROM #{table_name}"
    end

    def revert_archive_table(table_name, suffix=nil)
      old_table_name = [table_name, "datafix", migration_name].join("_").downcase
      log "Move old #{table_name} back" if self.respond_to?(:log)
      execute "TRUNCATE TABLE #{table_name}"
      execute "INSERT INTO #{table_name} SELECT * FROM archived_#{old_table_name}"
      execute "DROP TABLE archived_#{old_table_name}"
    end
  end
end
