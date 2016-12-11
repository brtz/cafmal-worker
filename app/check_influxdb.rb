require 'influxdb'
require './app/check_interface'

class CheckInfluxdb < CheckInterface
  def execute
    result = {}

    #@TODO username + pw support
    client = InfluxDB::Client.new host: @address, username: @username, password: @password, database: @index, retry: 5

    # prepare query
    query = @condition_query
    result_from_influxdb = client.query query

    case @condition_aggregator
    when 'influxdb_count'
=begin
    influxdb_count matches the amount of timeseries entries against the condition_value
=end
      count = 0
      result_from_influxdb.each do |result|
        count += result['values'].length
      end
      result['bool'] = count.send(@condition_operator, @condition_value)
      result['message'] = "count on influxdb: #{count} #{@condition_operator} #{@condition_value}"
      result['metric'] = count

    when 'influxdb_basic_all'
=begin
      influxdb_basic_all checks if all returned values are matching the condition
      e.g. SELECT "load1","load5" FROM "system" WHERE time > now() - 1h GROUP BY "host"
      result:
      [
        {
          values => [
            {
              "time"=>"timestamp1"
              "load1"=>0.3,
              "load5"=>0.2
            },
            {
              "time"=>"timestamp2"
              "load1"=>0.3,
              "load5"=>0.2
            }
          ]
        },
      ]

    so this condition_aggregator picks all the values (0.3,0.2,0.3,0.2) and checks them
    against condition_operator and condition_value (<=, 0.4). If all of them return true,
    the check will throw an event.
=end
      count_compared = 0
      matched = []
      result_from_influxdb.each do |result|
        result['values'].each do |value|
          value.each do |field, fieldvalue|
            next if field == "time"
            count_compared += 1
            if fieldvalue.send(@condition_operator, @condition_value)
              matched.push({
                name: result['name'],
                tags: result['tags'],
                field: field,
                fieldvalue: fieldvalue
              })
            end
          end
        end
      end
      if matched.length == count_compared
        result['bool'] = true
        result['message'] = "All (#{matched.length}/#{count_compared}) measurements match the query"
        result['metric'] = matched.length
      else
        result['bool'] = false
        result['message'] = "#{count_compared - matched.length} measurements did not match the query"
        result['metric'] = count_compared - matched.length
      end

    when 'influxdb_basic_distinct'
=begin
      If any of the measurements matches the query, it will throw an event
=end
      matched = []
      result_from_influxdb.each do |result|
        result['values'].each do |value|
          value.each do |field, fieldvalue|
            next if field == "time"
            if fieldvalue.send(@condition_operator, @condition_value)
              matched.push({
                name: result['name'],
                tags: result['tags'],
                field: field,
                fieldvalue: fieldvalue
              })
            end
          end
        end
      end
      if matched.length > 0
        result['bool'] = true
        result['message'] = "These measurements matched the query: #{matched.to_json}"
        result['metric'] = matched.length
      else
        result['bool'] = false
        result['message'] = "No measurements matched the query"
        result['metric'] = matched.length
      end

    end

    return result

  end
end
