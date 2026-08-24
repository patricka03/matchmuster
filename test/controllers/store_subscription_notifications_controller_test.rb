require "test_helper"

class StoreSubscriptionNotificationsControllerTest <
  ActionDispatch::IntegrationTest

  setup do
    @google_payload = {
      "message" => {
        "messageId" =>
          "google-controller-message-123",
        "data" =>
          "encoded-google-notification"
      },
      "subscription" =>
        "projects/matchmuster/subscriptions/store"
    }

    @apple_payload = {
      "signedPayload" =>
        "signed-apple-controller-notification"
    }
  end

  test "Google Play endpoint records pending notification" do
    assert_difference(
      "StoreSubscriptionEvent.count",
      1
    ) do
      assert_no_difference(
        "TeamEntitlement.count"
      ) do
        post google_endpoint,
             params: @google_payload,
             as: :json
      end
    end

    assert_response :accepted

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      true,
      body.fetch(
        "received"
      )
    )

    event =
      StoreSubscriptionEvent.last

    assert_equal(
      "google_play",
      event.provider
    )

    assert_equal(
      "google-controller-message-123",
      event.provider_event_id
    )

    assert event.pending?
    assert event.verification_pending?
    assert_nil event.team
  end

  test "Apple endpoint records pending notification" do
    assert_difference(
      "StoreSubscriptionEvent.count",
      1
    ) do
      post apple_endpoint,
           params: @apple_payload,
           as: :json
    end

    assert_response :accepted

    event =
      StoreSubscriptionEvent.last

    assert_equal(
      "apple",
      event.provider
    )

    assert_equal(
      @apple_payload,
      event.raw_payload
    )

    assert event.verification_pending?
  end

  test "identical Google notification replay is accepted" do
    post google_endpoint,
         params: @google_payload,
         as: :json

    assert_response :accepted

    assert_no_difference(
      "StoreSubscriptionEvent.count"
    ) do
      post google_endpoint,
           params: @google_payload,
           as: :json
    end

    assert_response :accepted
  end

  test "conflicting Google notification is rejected" do
    post google_endpoint,
         params: @google_payload,
         as: :json

    assert_response :accepted

    conflicting_payload =
      @google_payload.deep_dup

    conflicting_payload[
      "message"
    ][
      "data"
    ] =
      "different-notification-data"

    assert_no_difference(
      "StoreSubscriptionEvent.count"
    ) do
      post google_endpoint,
           params:
             conflicting_payload,
           as: :json
    end

    assert_response :conflict

    body =
      JSON.parse(
        response.body
      )

    assert_includes(
      body.fetch(
        "error"
      ),
      "reused with different data"
    )
  end

  test "invalid Google notification is rejected" do
    invalid_payload = {
      "message" => {
        "data" =>
          "missing-message-id"
      }
    }

    assert_no_difference(
      "StoreSubscriptionEvent.count"
    ) do
      post google_endpoint,
           params:
             invalid_payload,
           as: :json
    end

    assert_response :bad_request

    body =
      JSON.parse(
        response.body
      )

    assert_includes(
      body.fetch(
        "error"
      ),
      "message ID is missing"
    )
  end

  test "invalid Apple notification is rejected" do
    assert_no_difference(
      "StoreSubscriptionEvent.count"
    ) do
      post apple_endpoint,
           params: {},
           as: :json
    end

    assert_response :bad_request

    body =
      JSON.parse(
        response.body
      )

    assert_includes(
      body.fetch(
        "error"
      ),
      "signed notification payload is missing"
    )
  end

  private

  def google_endpoint
    "/subscriptions/google_play/notifications"
  end

  def apple_endpoint
    "/subscriptions/apple/notifications"
  end
end
