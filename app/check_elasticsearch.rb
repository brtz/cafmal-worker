require 'elasticsearch'
require './app/check_interface'

class CheckElasticsearch < CheckInterface
  def execute
    result = {}

    #@TODO username + pw support
    es_url = @protocol + @address + ':' + @port.to_s + '/' + @index
    client = Elasticsearch::Client.new url: es_url
    case @condition_aggregator
    when 'agg_sum'
      result_from_es = client.count q: @condition_query
    end

    case @condition_operand
    when '>'
      result['bool'] = result_from_es['count'] > @condition_value
      result['message'] = "count on elasticsearch: #{result_from_es['count']} > #{@condition_value}"
    when '<'
      result['bool'] = result_from_es['count'] < @condition_value
      result['message'] = "count on elasticsearch: #{result_from_es['count']} < #{@condition_value}"
    end

    return result

  end
end
