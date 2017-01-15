require 'sidekiq'
require 'sidekiq-cron'
require 'sidekiq-limit_fetch'
require 'cafmal'
require 'json'

# check required envs
missing_env_vars = []
missing_env_vars.push('CAFMAL_API_URL') if ENV['CAFMAL_API_URL'].nil?
missing_env_vars.push('CAFMAL_WORKER_UUID') if ENV['CAFMAL_WORKER_UUID'].nil?
missing_env_vars.push('CAFMAL_WORKER_DATASOURCE_ID') if ENV['CAFMAL_WORKER_DATASOURCE_ID'].nil?
missing_env_vars.push('CAFMAL_WORKER_EMAIL') if ENV['CAFMAL_WORKER_EMAIL'].nil?
missing_env_vars.push('CAFMAL_WORKER_PASSWORD') if ENV['CAFMAL_WORKER_PASSWORD'].nil?
abort "Missing required env vars! (#{missing_env_vars.join(',')})" if missing_env_vars.length > 0

Sidekiq.configure_server do |config|
  config.redis = {
    host: "redis" || ENV['CAFMAL_WORKER_CACHE_HOST'],
    port: 6379 || ENV['CAFMAL_WORKER_CACHE_PORT'].to_i,
    db: 0 || ENV['CAFMAL_WORKER_CACHE_DB'].to_i,
    password: "foobar" || ENV['CAFMAL_WORKER_CACHE_PASSWORD'],
    namespace: "worker"
  }
end

class CafmalWorker
  include Sidekiq::Worker
  require './app/check_elasticsearch'
  require './app/check_influxdb'

  def perform(*args)
    api_url = args[0]['api_url']
    uuid = args[0]['uuid']
    datasource_id = args[0]['datasource_id'].to_i
    email = args[0]['email']
    password = args[0]['password']

    checks_to_run = []

    auth = Cafmal::Auth.new(api_url)
    auth.login(email, password)

    # register worker (update if already registered)
    existing_worker_id = nil
    worker = Cafmal::Worker.new(api_url, auth.token)
    workers = JSON.parse(worker.list.body)
    workers.each do |found_worker|
      if found_worker['uuid'] == uuid
        existing_worker_id = found_worker['id']
        break;
      end
    end

    params_to_w = {}
    params_to_w['uuid'] = uuid
    params_to_w['heartbeat_received_at'] = DateTime.now.new_offset(0)
    if existing_worker_id.nil?
      create_worker_response = worker.create(params_to_w).body
    else
      params_to_w['id'] = existing_worker_id
      create_worker_response = worker.update(params_to_w).body
    end
    logger.info "Registered worker (#{uuid}, datasource: #{datasource_id}): #{JSON.parse(create_worker_response)['id']}"

    # get all the checks
    check = Cafmal::Check.new(api_url, auth.token)
    checks = JSON.parse(check.list.body)

    # filter
    checks.each do |check|
      next if check['datasource_id'] != datasource_id
      next unless check['deleted_at'].nil?
      next if check['is_locked']
      next if DateTime.parse(check['updated_at']) + Rational(check['interval'], 86400) >= DateTime.now.new_offset(0)
      checks_to_run.push(check)
    end

    logger.info "Checks to run:"
    logger.info checks_to_run.to_json

    checks_to_run.each do |check|
      logger.info "Going to run check: #{check['name']} from team: #{check['team_id']}"
      params = check
      params['is_locked'] = true
      check_res = Cafmal::Check.new(api_url, auth.token)
      locked = check_res.update(params).body

      # run check itself
      datasource = Cafmal::Datasource.new(api_url, auth.token)
      datasources = JSON.parse(datasource.list.body)
      checktype = nil
      datasource_to_use = nil
      datasources.each do |datasource|
        if datasource['id'] == check['datasource_id']
          next unless datasource['deleted_at'].nil?
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
          check['index'],
          check['condition_query'],
          check['condition_operator'],
          check['condition_aggregator'],
          check['condition_value'],
          datasource_to_use['username'],
          datasource_to_use['password']
        )
        result = check_to_perform.execute

        logger.info result

        if result['bool']
          event = Cafmal::Event.new(api_url, auth.token)
          params_to_e = {}
          params_to_e['team_id'] = check['team_id']
          params_to_e['name'] = check['category'] + '.' + check['name']
          params_to_e['message'] = result['message']
          params_to_e['kind'] = 'check'
          params_to_e['severity'] = check['severity']
          params_to_e['metric'] = result['metric'].to_s

          create_event_response = event.create(params_to_e).body
          logger.info "Created new event: #{JSON.parse(create_event_response)['id']}"
        end
      rescue Exception => e
        logger.error "Check failed! #{check} | #{e.inspect}"
        event = Cafmal::Event.new(api_url, auth.token)
        params_to_e = {}
        params_to_e['team_id'] = check['team_id']
        params_to_e['name'] = 'check_failed'
        params_to_e['message'] = "Check #{check['name']} failed: #{e.inspect}"
        params_to_e['kind'] = 'check'
        params_to_e['severity'] = 'error'

        create_event_response = event.create(params_to_e).body
        logger.info "Created new event: #{JSON.parse(create_event_response)['id']}"
      end

      params['is_locked'] = false
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

Sidekiq::Cron::Job.create(
  name: "cafmalWorker-#{ENV['CAFMAL_WORKER_UUID']}",
  cron: '*/30 * * * * *',
  class: 'CafmalWorker',
  queue: "cafmalQueue-worker-#{ENV['CAFMAL_WORKER_DATASOURCE_ID']}",
  args: {
    api_url: ENV['CAFMAL_API_URL'],
    uuid: ENV['CAFMAL_WORKER_UUID'],
    datasource_id: ENV['CAFMAL_WORKER_DATASOURCE_ID'],
    email: ENV['CAFMAL_WORKER_EMAIL'],
    password: ENV['CAFMAL_WORKER_PASSWORD']
  }
)

Sidekiq::Queue["cafmalQueue-#{ENV['CAFMAL_WORKER_DATASOURCE_ID']}"].limit = 1
