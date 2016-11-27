class CheckInterface
  @address = nil
  @port = nil
  @protocol = nil
  @index = nil
  @condition_query = nil
  @condition_operand = nil
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
    condition_operand,
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
  @condition_operand = '>' if (condition_operand == 'greaterThan')
  @condition_operand = '<' if (condition_operand == 'lowerThan')
  @condition_aggregator = condition_aggregator
  @condition_value = condition_value

  end

  def execute(*args)
    abort 'not implemented'
  end
end
