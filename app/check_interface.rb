class CheckInterface
  @address = nil
  @port = nil
  @protocol = nil
  @index = nil
  @condition_query = nil
  @condition_operator = nil
  @condition_aggregator = nil
  @condition_value = nil
  @username = nil
  @password = nil

  def initialize(
    address,
    port,
    protocol,
    index,
    condition_query,
    condition_operator,
    condition_aggregator,
    condition_value,
    username = "",
    password = ""
  )
  @address = address
  @port = port
  @protocol = protocol
  @index = index
  @condition_query = condition_query
  case condition_operator
  when 'lowerThan'
    @condition_operator = '<'
  when 'greaterThan'
    @condition_operator = '>'
  when 'lowerThanOrEqual'
    @condition_operator = '<='
  when 'greaterThanOrEqual'
    @condition_operator = '>='
  when 'equal'
    @condition_operator = '=='
  end
  @condition_aggregator = condition_aggregator
  @condition_value = condition_value

  end

  def execute(*args)
    abort 'not implemented'
  end
end
