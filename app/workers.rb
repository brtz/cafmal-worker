require 'sidekiq'
require 'sidekiq-cron'
require 'cafmal'
require 'json'

Sidekiq.configure_server do |config|
  config.redis = {
    host: "redis" || ENV["CAFMAL-WORKER_CACHE_HOST"],
    port: 6379 || ENV["CAFMAL-WORKER_CACHE_PORT"].to_i,
    db: 0 || ENV["CAFMAL-WORKER_CACHE_DB"].to_i,
    password: "foobar" || ENV["CAFMAL-WORKER_CACHE_PASSWORD"],
    namespace: "worker"
  }
end

schedule_file = "config/schedule.yml"
if File.exists?(schedule_file) && Sidekiq.server?
  Sidekiq::Cron::Job.load_from_hash YAML.load_file(schedule_file)
end

class CafmalWorker
  include Sidekiq::Worker
  require './app/check_elasticsearch'
  require './app/check_influxdb'

  def perform()
    api_url = ENV['CAFMAL_API_URL']
    email = 'worker@example.com' || ENV['CAFMAL_WORKER_EMAIL']
    password = 'barfoo' || ENV['CAFMAL_WORKER_PASSOWRD']
    checks_to_run = []

    auth = Cafmal::Auth.new(ENV['CAFMAL_API_URL'])
    auth.login(email, password)

    # get all the checks
    check = Cafmal::Check.new(api_url, auth.token)
    checks = JSON.parse(check.list)

    # filter deleted_at
    checks.each do |check|
      check['last_ran_at'] = DateTime.now.new_offset(0) if check['last_ran_at'].nil?

      next unless check['deleted_at'].nil?
      next if check['is_locked']
      next if DateTime.parse(check['last_ran_at']) + Rational(check['interval'], 86400) >= DateTime.now.new_offset(0)
      checks_to_run.push(check)
    end

    logger.info "Checks to run:"
    logger.info checks_to_run.to_json

    checks_to_run.each do |check|
      logger.info "Going to run check: #{check['name']} from team: #{check['team_id']}"
      params = check
      params['is_locked'] = true
      check_res = Cafmal::Check.new(api_url, auth.token)
      locked = check_res.update(params)

      # run check itself
      datasource = Cafmal::Datasource.new(api_url, auth.token)
      datasources = JSON.parse(datasource.list)
      checktype = nil
      datasource_to_use = nil
      datasources.each do |datasource|
        if datasource['id'] == check['datasource_id']
          checktype = datasource['sourcetype']
          datasource_to_use = datasource
          break
        end
      end

      if checktype.nil?
        logger.error 'Datasource type is not available!'
        next
      end

      begin
        check_to_perform = ('Check' + checktype.capitalize).constantize.new(
          datasource_to_use['address'],
          datasource_to_use['port'],
          datasource_to_use['protocol'],
          datasource_to_use['index'],
          check['condition_query'],
          check['condition_operand'],
          check['condition_aggregator'],
          check['condition_value'],
          datasource_to_use['username'],
          datasource_to_use['password']
        )
        result = check_to_perform.execute

        if result['bool']
          event = Cafmal::Event.new(api_url, auth.token)
          params_to_e = {}
          params_to_e['team_id'] = check['team_id']
          params_to_e['name'] = check['name']
          params_to_e['message'] = result['message']
          params_to_e['kind'] = 'check'
          params_to_e['severity'] = check['severity']

          create_event_response = event.create(params_to_e)
          logger.info "Created new event: #{JSON.parse(create_event_response)['id']}"
        end
      rescue Exception => e
        logger.error "Check failed! #{check} | #{e.inspect}"
        #@TODO sent event
      end

      params['is_locked'] = false
      params['last_ran_at'] = DateTime.now().new_offset(0)
      finished_run = check_res.update(params)
    end

  end

  def constantize(camel_cased_word)
    unless /\A(?:::)?([A-Z]\w*(?:::[A-Z]\w*)*)\z/ =~ camel_cased_word
      raise NameError, "#{camel_cased_word.inspect} is not a valid constant name!"
    end

    Object.module_eval("::#{$1}", __FILE__, __LINE__)
  end

end
