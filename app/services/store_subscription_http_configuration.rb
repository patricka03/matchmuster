class StoreSubscriptionHttpConfiguration
  DEFAULT_OPEN_TIMEOUT = 5.0
  DEFAULT_READ_TIMEOUT = 15.0

  OPEN_TIMEOUT_KEY =
    "STORE_SUBSCRIPTION_OPEN_TIMEOUT_SECONDS"

  READ_TIMEOUT_KEY =
    "STORE_SUBSCRIPTION_READ_TIMEOUT_SECONDS"

  class ConfigurationError < StandardError; end

  class << self
    def open_timeout(environment: ENV)
      timeout(
        environment: environment,
        key: OPEN_TIMEOUT_KEY,
        default: DEFAULT_OPEN_TIMEOUT,
        maximum: 30.0
      )
    end

    def read_timeout(environment: ENV)
      timeout(
        environment: environment,
        key: READ_TIMEOUT_KEY,
        default: DEFAULT_READ_TIMEOUT,
        maximum: 60.0
      )
    end

    private

    def timeout(environment:, key:, default:, maximum:)
      raw_value = environment[key].to_s.strip
      return default if raw_value.empty?

      value = Float(raw_value)

      unless value.positive? && value <= maximum
        raise ConfigurationError,
              "#{key} must be greater than 0 and no more than #{maximum.to_i}"
      end

      value
    rescue ArgumentError, TypeError
      raise ConfigurationError,
            "#{key} must be a valid number"
    end
  end
end
