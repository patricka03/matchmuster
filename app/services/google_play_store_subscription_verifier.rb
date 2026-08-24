class GooglePlayStoreSubscriptionVerifier
  class << self
    def call(event:)
      new.call(
        event: event
      )
    end
  end

  def initialize(
    api_client: nil,
    package_name:
      ENV[
        "GOOGLE_PLAY_PACKAGE_NAME"
      ]
  )
    @api_client =
      api_client

    @package_name =
      package_name.to_s.strip
  end

  def call(event:)
    ensure_configured!

    decoded =
      GooglePlayStoreNotificationDecoder.call(
        event: event,
        package_name:
          package_name
      )

    return informational_result(
      event: event,
      decoded: decoded
    ) if informational?(
      decoded
    )

    purchase =
      api_client!.fetch_subscription(
        package_name:
          package_name,
        purchase_token:
          decoded.fetch(
            :purchase_token
          )
      )

    GooglePlaySubscriptionStateMapper.call(
      decoded_notification:
        decoded,
      purchase: purchase
    )

  rescue GooglePlayStoreNotificationDecoder::
           InvalidNotification,
         GooglePlaySubscriptionStateMapper::
           InvalidPurchase,
         GooglePlayDeveloperApiClient::
           NotFound => error

    raise StoreSubscriptionEventVerificationService::
            RejectedNotification,
          error.message

  rescue GooglePlayDeveloperApiClient::
           AuthenticationError,
         GooglePlayDeveloperApiClient::
           RequestFailed => error

    raise StoreSubscriptionEventVerificationService::
            TemporaryFailure,
          error.message
  end

  private

  attr_reader :api_client,
              :package_name

  def ensure_configured!
    return if
      package_name.present?

    raise StoreSubscriptionEventVerificationService::
            TemporaryFailure,
          "Google Play package name is not configured"
  end

  def api_client!
    return api_client if
      api_client

    "GooglePlayDeveloperApiClient"
      .constantize
      .new

  rescue NameError
    raise StoreSubscriptionEventVerificationService::
            TemporaryFailure,
          "Google Play Developer API client is not configured"
  end

  def informational?(decoded)
    %w[
      test_notification
      unsupported
    ].include?(
      decoded.fetch(
        :kind
      )
    )
  end

  def informational_result(
    event:,
    decoded:
  )
    kind =
      decoded.fetch(
        :kind
      )

    environment =
      kind ==
        "test_notification" ?
          "sandbox" :
          event.environment

    {
      event_type:
        "google_#{kind}",

      environment:
        environment,

      provider_subscription_id:
        nil,

      occurred_at:
        decoded[
          :event_time
        ],

      metadata: {
        "google_notification_kind" =>
          kind
      }
    }
  end
end
