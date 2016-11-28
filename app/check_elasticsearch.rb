require 'elasticsearch'
require './app/check_interface'

class CheckElasticsearch < CheckInterface
  def execute
    result = {}

    #@TODO username + pw support
    es_url = @protocol + @address + ':' + @port.to_s + '/' + @index
    client = Elasticsearch::Client.new url: es_url

    # prepare query
    query = @condition_query
    query.delete!("\n")
    query.delete!("\r")

    case @condition_aggregator
    when 'agg_sum'
      #@TODO add index here, simple index: @index, does not work, as wildcards are not supported
      result_from_es = client.count body: query
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
