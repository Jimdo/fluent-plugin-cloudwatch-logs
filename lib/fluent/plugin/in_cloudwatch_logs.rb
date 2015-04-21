module Fluent
  class CloudwatchLogsInput < Input
    Plugin.register_input('cloudwatch_logs', self)

    config_param :aws_key_id, :string, :default => nil
    config_param :aws_sec_key, :string, :default => nil
    config_param :region, :string, :default => nil
    config_param :tag, :string
    config_param :log_group_name, :string
    config_param :log_stream_name, :string
    config_param :state_file, :string
    config_param :fetch_interval, :time, default: 60

    def initialize
      super

      require 'aws-sdk-core'
    end

    def start
      options = {}
      options[:credentials] = Aws::Credentials.new(@aws_key_id, @aws_sec_key) if @aws_key_id && @aws_sec_key
      options[:region] = @region if @region
      options[:ssl_ca_bundle] = ENV['AWS_SSL_CA_BUNDLE'] if ENV.has_key?('AWS_SSL_CA_BUNDLE')
      @logs = Aws::CloudWatchLogs::Client.new(options)

      @finished = false
      @thread = Thread.new(&method(:run))
    end

    def shutdown
      @finished = true
      @thread.join
    end

    private
    def next_token
      return nil unless File.exist?(@state_file)
      File.read(@state_file).chomp
    end

    def store_next_token(token)
      open(@state_file, 'w') do |f|
        f.write token
      end
    end

    def run
      @next_fetch_time = Time.now

      until @finished
        if Time.now > @next_fetch_time
          @next_fetch_time += @fetch_interval

          events = get_events
          events.each do |event|
            time = (event.timestamp / 1000).floor
            Engine.emit(@tag, time, {'message' => event.message})
          end
        end
        sleep 1
      end
    end

    def get_events
      request = {
        log_group_name: @log_group_name,
        log_stream_name: @log_stream_name,
      }
      request[:next_token] = next_token if next_token
      response = @logs.get_log_events(request)
      store_next_token(response.next_forward_token)

      response.events
    end
  end
end
