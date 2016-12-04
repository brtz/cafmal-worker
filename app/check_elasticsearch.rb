require 'elasticsearch'
require './app/check_interface'

class CheckElasticsearch < CheckInterface
  def execute
    result = {}

    #@TODO username + pw support
    es_url = @protocol + @address + ':' + @port.to_s + '/'
    client = Elasticsearch::Client.new url: es_url

    # prepare query
    query = @condition_query
    query.delete!("\n")
    query.delete!("\r")

    case @condition_aggregator
    when 'elasticsearch_count'
      if !@index.nil?
        result_from_es = client.count index: "#{@index}", body: query
      else
        result_from_es = client.count body: query
      end
    end

    result['bool'] = result_from_es['count'].send(@condition_operator, @condition_value)
    result['message'] = "count on elasticsearch: #{result_from_es['count']} #{@condition_operator} #{@condition_value}"
    result['metric'] = result_from_es['count']

    return result

  end
end
