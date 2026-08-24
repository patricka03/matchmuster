require "test_helper"

class StoreSubscriptionEventIngestorTest <
  ActiveSupport::TestCase

  setup do
    @google_payload = {
      "message" => {
        "messageId" =>
          "google-message-123",
        "data" =>
          "encoded-google-notification"
      },
      "subscription" =>
        "projects/matchmuster/subscriptions/store"
    }

    @apple_payload = {
      "signedPayload" =>
        "signed-apple-notification"
    }
  end

  test "records Google Play notification for verification" do
    event =
      ingest(
        provider: "google_play",
        raw_payload: @google_payload
      )

    assert_equal(
      "google_play",
      event.provider
    )

    assert_equal(
      "google-message-123",
      event.provider_event_id
    )

    assert_equal(
      "notification_received",
      event.event_type
    )

    assert_equal(
      "sandbox",
      event.environment
    )

    assert_equal(
      @google_payload,
      event.raw_payload
    )

    assert event.pending?
    assert event.verification_pending?
    assert_nil event.team
  end

  test "records Apple notification using stable payload digest" do
    event =
      ingest(
        provider: "apple",
        raw_payload: @apple_payload
      )

    expected_digest =
      Digest::SHA256.hexdigest(
        @apple_payload.fetch(
          "signedPayload"
        )
      )

    assert_equal(
      "apple",
      event.provider
    )

    assert_equal(
      "sha256:#{expected_digest}",
      event.provider_event_id
    )

    assert_equal(
      @apple_payload,
      event.raw_payload
    )

    assert event.verification_pending?
  end

  test "identical notification replay is idempotent" do
    original =
      ingest(
        provider: "google_play",
        raw_payload: @google_payload
      )

    replay = nil

    assert_no_difference(
      "StoreSubscriptionEvent.count"
    ) do
      replay =
        ingest(
          provider: "google_play",
          raw_payload: @google_payload
        )
    end

    assert_equal(
      original.id,
      replay.id
    )
  end

  test "same identifier with different payload is rejected" do
    ingest(
      provider: "google_play",
      raw_payload: @google_payload
    )

    conflicting_payload =
      @google_payload.deep_dup

    conflicting_payload[
      "message"
    ][
      "data"
    ] =
      "different-data"

    assert_raises(
      StoreSubscriptionEventIngestor::
        PayloadConflict
    ) do
      ingest(
        provider: "google_play",
        raw_payload:
          conflicting_payload
      )
    end

    stored_event =
      StoreSubscriptionEvent.find_by!(
        provider: "google_play",
        provider_event_id:
          "google-message-123"
      )

    assert_equal(
      @google_payload,
      stored_event.raw_payload
    )
  end

  test "unsupported provider is rejected" do
    assert_raises(
      StoreSubscriptionEventIngestor::
        UnsupportedProvider
    ) do
      ingest(
        provider: "fake_store",
        raw_payload: {}
      )
    end
  end

  test "unsupported environment is rejected" do
    assert_raises(
      StoreSubscriptionEventIngestor::
        UnsupportedEnvironment
    ) do
      ingest(
        provider: "google_play",
        raw_payload:
          @google_payload,
        environment: "testing"
      )
    end
  end

  test "payload must be a JSON object" do
    assert_raises(
      StoreSubscriptionEventIngestor::
        InvalidPayload
    ) do
      ingest(
        provider: "google_play",
        raw_payload: [
          "invalid"
        ]
      )
    end
  end

  test "Google notification requires message ID" do
    payload = {
      "message" => {
        "data" =>
          "encoded-google-notification"
      }
    }

    assert_raises(
      StoreSubscriptionEventIngestor::
        InvalidPayload
    ) do
      ingest(
        provider: "google_play",
        raw_payload: payload
      )
    end
  end

  test "Apple notification requires signed payload" do
    assert_raises(
      StoreSubscriptionEventIngestor::
        InvalidPayload
    ) do
      ingest(
        provider: "apple",
        raw_payload: {}
      )
    end
  end

  private

  def ingest(
    provider:,
    raw_payload:,
    environment: nil
  )
    StoreSubscriptionEventIngestor.call(
      provider: provider,
      raw_payload: raw_payload,
      environment: environment
    )
  end
end
