require 'mongo'

module Bipbip
  class Plugin::Mongodb < Plugin
    def metrics_schema
      [
        { name: 'op_inserts', type: 'gauge' },
        { name: 'op_queries', type: 'gauge' },
        { name: 'op_updates', type: 'gauge' },
        { name: 'op_deletes', type: 'gauge' },
        { name: 'op_getmores', type: 'gauge' },
        { name: 'op_commands', type: 'gauge' },
        { name: 'connections_current', type: 'gauge' },
        { name: 'mem_resident', type: 'gauge', unit: 'MB' },
        { name: 'mem_mapped', type: 'gauge', unit: 'MB' },
        { name: 'mem_pagefaults', type: 'gauge', unit: 'faults' },
        { name: 'globalLock_currentQueue', type: 'gauge' },
        { name: 'replication_lag', type: 'gauge', unit: 'Seconds' },
        { name: 'slow_queries_count', type: 'gauge_f', unit: 'Queries' },
        { name: 'slow_queries_time_avg', type: 'gauge_f', unit: 'Seconds' },
        { name: 'slow_queries_time_max', type: 'gauge_f', unit: 'Seconds' },
        { name: 'total_index_size', type: 'gauge', unit: 'MB' },
        { name: 'total_index_size_percentage_of_memory', type: 'gauge', unit: '%' }
      ]
    end

    def monitor
      status = fetch_server_status
      all_index_size = total_index_size

      data = {}

      if status['opcounters']
        data['op_inserts'] = status['opcounters']['insert'].to_i
        data['op_queries'] = status['opcounters']['query'].to_i
        data['op_updates'] = status['opcounters']['update'].to_i
        data['op_deletes'] = status['opcounters']['delete'].to_i
        data['op_getmores'] = status['opcounters']['getmore'].to_i
        data['op_commands'] = status['opcounters']['command'].to_i
      end
      if status['connections']
        data['connections_current'] = status['connections']['current'].to_i
      end
      if status['mem']
        data['mem_resident'] = status['mem']['resident'].to_i
        data['mem_mapped'] = status['mem']['mapped'].to_i
      end
      if status['extra_info']
        data['mem_pagefaults'] = status['extra_info']['page_faults'].to_i
      end
      if status['globalLock'] && status['globalLock']['currentQueue']
        data['globalLock_currentQueue'] = status['globalLock']['currentQueue']['total'].to_i
      end
      if status['repl'] && status['repl']['secondary'] == true
        data['replication_lag'] = replication_lag
      end

      if status['repl'] && status['repl']['ismaster'] == true
        slow_queries_status = fetch_slow_queries_status

        data['slow_queries_count'] = slow_queries_status['total']['count']
        data['slow_queries_time_avg'] = slow_queries_status['total']['time'].to_f / (slow_queries_status['total']['count'].to_f.nonzero? || 1)
        data['slow_queries_time_max'] = slow_queries_status['max']['time']
      end

      unless router?
        data['total_index_size'] = all_index_size / (1024 * 1024)
        data['total_index_size_percentage_of_memory'] = (all_index_size.to_f / total_system_memory.to_f) * 100
      end

      data
    end

    private

    def slow_query_threshold
      config['slow_query_threshold'] || 0
    end

    # @return [Mongo::Client]
    def mongodb_client
      if @mongodb_client.nil?
        address = config['hostname'] + ':' + config['port'].to_s
        options = {
          socket_timeout: 2,
          connect: :direct,
          logger: Logger.new('/dev/null')
        }
        options[:user] = config['user'] if config.key?('user')
        options[:password] = config['password'] if config.key?('password')
        options[:database] = config['database'] if config.key?('database')
        @mongodb_client = Mongo::Client.new([address], options)
      end
      @mongodb_client
    end

    # @return [Mongo::DB]
    def mongodb_database(db_name)
      mongodb_client.use(db_name)
    end

    def fetch_server_status
      mongodb_database('admin').command('serverStatus' => 1).documents.first
    end

    def fetch_replica_status
      mongodb_database('admin').command('replSetGetStatus' => 1).documents.first
    end

    def slow_query_last_check
      old = (@slow_query_last_check || Time.now)
      @slow_query_last_check = Time.now
      old
    end

    # @return [Integer]
    def total_index_size
      database_names_ignore = %w(admin system local)
      database_list = (mongodb_client.database_names - database_names_ignore).map { |name| mongodb_database(name) }

      database_list.map do |database|
        results = database.command('dbstats' => 1)
        results.count.zero? ? 0 : results.documents.first['indexSize']
      end.reduce(0, :+)
    end

    # @return [Integer]
    def total_system_memory
      `free -b`.lines.to_a[1].split[1].to_i
    end

    def router?
      fetch_server_status['process'] == 'mongos'
    end

    def fetch_slow_queries_status
      timestamp_last_check = slow_query_last_check
      time_period = Time.now - timestamp_last_check

      database_names_ignore = %w(admin system local)
      database_list = (mongodb_client.database_names - database_names_ignore).map { |name| mongodb_database(name) }

      stats = database_list.reduce('total' => { 'count' => 0, 'time' => 0 }, 'max' => { 'time' => 0 }) do |memo, database|
        results = database['system.profile'].find.aggregate(
          [
            { '$match' => { 'millis' => { '$gte' => slow_query_threshold }, 'ts' => { '$gt' => timestamp_last_check } } },
            { '$group' => {
              '_id' => 'null',
              'total_count' => { '$sum' => 1 },
              'total_time' => { '$sum' => '$millis' },
              'max_time' => { '$max' => '$millis' }
            } }
          ]
        )

        unless results.count.zero?
          result = results.first
          max_time = result['max_time'].to_f / 1000

          memo['total']['count'] += result['total_count']
          memo['total']['time'] += result['total_time'].to_f / 1000
          memo['max']['time'] = max_time if memo['max']['time'] < max_time
        end

        memo
      end

      stats['total'].each { |metric, value| stats['total'][metric] = value / time_period }

      stats
    end

    def replication_lag
      status = fetch_replica_status
      member_list = status['members']
      primary = member_list.find { |member| member['stateStr'] == 'PRIMARY' }
      secondary = member_list.find { |member| member['stateStr'] == 'SECONDARY' && member['self'] == true }

      raise "No primary member in replica `#{status['set']}`" if primary.nil?
      raise "Cannot find itself as secondary member in replica `#{status['set']}`" if secondary.nil?

      (secondary['optime'].seconds - primary['optime'].seconds)
    end
  end
end
