class StoreSubscriptionNotificationsController <
  ApplicationController

  wrap_parameters false

  def google_play
    ingest!(
      provider: "google_play"
    )
  end

  def apple
    ingest!(
      provider: "apple"
    )
  end

  private

  def ingest!(provider:)
    StoreSubscriptionEventIngestor.call(
      provider: provider,
      raw_payload:
        parsed_raw_payload
    )

    render json: {
      received: true
    }, status: :accepted

  rescue StoreSubscriptionEventIngestor::
           PayloadConflict => error

    render json: {
      error: error.message
    }, status: :conflict

  rescue StoreSubscriptionEventIngestor::
           InvalidPayload,
         StoreSubscriptionEventIngestor::
           UnsupportedProvider,
         StoreSubscriptionEventIngestor::
           UnsupportedEnvironment => error

    render json: {
      error: error.message
    }, status: :bad_request
  end

  def parsed_raw_payload
    JSON.parse(
      request.raw_post
    )
  rescue JSON::ParserError
    raise StoreSubscriptionEventIngestor::
            InvalidPayload,
          "Store notification payload must be valid JSON"
  end
end
