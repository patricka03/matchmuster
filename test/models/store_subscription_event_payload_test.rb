require "test_helper"

class StoreSubscriptionEventPayloadTest <
  ActiveSupport::TestCase

  setup do
    @team =
      Team.create!(
        name: "Payload Test FC"
      )
  end

  test "new event has an empty raw payload by default" do
    event =
      StoreSubscriptionEvent.new(
        valid_attributes.except(
          :raw_payload
        )
      )

    assert(
      event.valid?,
      event.errors.full_messages.to_sentence
    )

    assert_equal(
      {},
      event.raw_payload
    )
  end

  test "raw store notification can be retained" do
    payload = {
      "message" => {
        "messageId" =>
          "google-message-123",
        "data" =>
          "encoded-store-notification"
      }
    }

    event =
      StoreSubscriptionEvent.create!(
        valid_attributes.merge(
          raw_payload: payload
        )
      )

    assert_equal(
      payload,
      event.reload.raw_payload
    )
  end

  test "raw payload must be a JSON object" do
    event =
      StoreSubscriptionEvent.new(
        valid_attributes.merge(
          raw_payload: [
            "invalid",
            "payload"
          ]
        )
      )

    assert_not event.valid?

    assert_includes(
      event.errors[
        :raw_payload
      ],
      "must be a JSON object"
    )
  end

  private

  def valid_attributes
    {
      team: @team,
      provider: "google_play",
      provider_event_id:
        "google-payload-event-123",
      event_type:
        "notification_received",
      environment: "sandbox",
      processing_status: "pending",
      verification_status: "pending",
      metadata: {},
      raw_payload: {
        "message" => {
          "messageId" =>
            "google-message-123"
        }
      }
    }
  end
end
