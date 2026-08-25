class StoreSubscriptionAccountToken
  class InvalidPayload < StandardError; end
  class InvalidToken < StandardError; end
  class UnsupportedProvider < StandardError; end

  class << self
    def call(provider:, payload:)
      new(
        provider: provider,
        payload: payload
      ).call
    end
  end

  def initialize(provider:, payload:)
    @provider =
      provider.to_s

    unless payload.is_a?(Hash)
      raise InvalidPayload,
            "Store subscription payload must be an object"
    end

    @payload =
      payload.deep_stringify_keys
  end

  def call
    value =
      account_token
        .to_s
        .strip

    return nil if value.blank?

    unless value.match?(
      Team::BILLING_ACCOUNT_TOKEN_FORMAT
    )
      raise InvalidToken,
            "Store subscription account token must be a UUID"
    end

    value.downcase
  end

  private

  attr_reader :provider,
              :payload

  def account_token
    case provider
    when "apple"
      payload[
        "appAccountToken"
      ]

    when "google_play"
      payload.dig(
        "externalAccountIdentifiers",
        "obfuscatedExternalAccountId"
      )

    else
      raise UnsupportedProvider,
            "Unsupported subscription provider: #{provider}"
    end
  end
end
