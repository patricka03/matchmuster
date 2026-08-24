require "test_helper"

class StoreSubscriptionEventVerifierTest <
  ActiveSupport::TestCase

  setup do
    @event =
      StoreSubscriptionEvent.create!(
        provider: "google_play",
        provider_event_id:
          "verifier-router-event-123",
        event_type:
          "notification_received",
        environment: "sandbox",
        metadata: {},
        raw_payload: {
          "message" => {
            "messageId" =>
              "verifier-router-message-123"
          }
        }
      )
  end

  test "defines verifier for each supported provider" do
    assert_equal(
      "GooglePlayStoreSubscriptionVerifier",
      StoreSubscriptionEventVerifier::
        VERIFIER_CLASS_NAMES.fetch(
          "google_play"
        )
    )

    assert_equal(
      "AppleStoreSubscriptionVerifier",
      StoreSubscriptionEventVerifier::
        VERIFIER_CLASS_NAMES.fetch(
          "apple"
        )
    )
  end

  test "passes event to supplied provider verifier" do
    captured_event = nil

    fake_verifier =
      Object.new

    fake_verifier.define_singleton_method(
      :call
    ) do |event:|
      captured_event = event

      {
        event_type:
          "test_notification",
        environment:
          "sandbox",
        provider_subscription_id:
          nil,
        occurred_at:
          nil,
        metadata: {}
      }
    end

    result =
      StoreSubscriptionEventVerifier.call(
        event: @event,
        verifier: fake_verifier
      )

    assert_equal(
      @event,
      captured_event
    )

    assert_equal(
      @event,
      result
    )

    assert @event.reload.verified?
    assert @event.ignored?
  end

  test "unsupported provider is rejected" do
    assert_raises(
      StoreSubscriptionEventVerifier::
        UnsupportedProvider
    ) do
      StoreSubscriptionEventVerifier.verifier_for(
        "fake_store"
      )
    end
  end
end
