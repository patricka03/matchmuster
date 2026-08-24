require "test_helper"

class StoreSubscriptionEventVerificationServiceTest <
  ActiveSupport::TestCase

  setup do
    @team =
      Team.create!(
        name: "Verification Pipeline FC"
      )

    @starts_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @ends_at =
      @starts_at + 30.days

    @event_sequence = 0
  end

  test "verified result is normalized and processed" do
    event =
      create_event

    verify(
      event,
      verifier_returning(
        valid_result
      )
    )

    event.reload

    assert event.verified?
    assert event.processed?

    assert_equal(
      "subscription_activated",
      event.event_type
    )

    assert_equal(
      "google-subscription-verified",
      event.provider_subscription_id
    )

    assert_equal(
      @starts_at,
      event.occurred_at
    )

    entitlement =
      @team
        .reload
        .team_entitlement

    assert_equal(
      "active",
      entitlement.status
    )

    assert_equal(
      "google_play",
      entitlement.provider
    )

    assert_equal(
      "monthly",
      entitlement.billing_period
    )
  end

  test "rejected notification is recorded without processing" do
    event =
      create_event

    verifier =
      lambda do |event:|
        raise StoreSubscriptionEventVerificationService::
                RejectedNotification,
              "Invalid store signature"
      end

    result =
      verify(
        event,
        verifier
      )

    assert_equal(
      event,
      result
    )

    assert event.reload.verification_rejected?
    assert event.pending?

    assert_includes(
      event.verification_error,
      "Invalid store signature"
    )

    assert_nil(
      @team.reload.team_entitlement
    )
  end

  test "temporary verification failure is recorded and raised" do
    event =
      create_event

    verifier =
      lambda do |event:|
        raise StoreSubscriptionEventVerificationService::
                TemporaryFailure,
              "Store API unavailable"
      end

    assert_raises(
      StoreSubscriptionEventVerificationService::
        TemporaryFailure
    ) do
      verify(
        event,
        verifier
      )
    end

    event.reload

    assert event.verification_failed?
    assert event.pending?

    assert_includes(
      event.verification_error,
      "Store API unavailable"
    )
  end

  test "invalid verifier result is recorded as failure" do
    event =
      create_event

    assert_raises(
      StoreSubscriptionEventVerificationService::
        InvalidResult
    ) do
      verify(
        event,
        verifier_returning(
          [
            "not",
            "an",
            "object"
          ]
        )
      )
    end

    event.reload

    assert event.verification_failed?

    assert_includes(
      event.verification_error,
      "result must be an object"
    )
  end

  test "invalid verified environment is rejected as failure" do
    event =
      create_event

    result =
      valid_result.merge(
        environment: "testing"
      )

    assert_raises(
      StoreSubscriptionEventVerificationService::
        InvalidResult
    ) do
      verify(
        event,
        verifier_returning(
          result
        )
      )
    end

    event.reload

    assert event.verification_failed?

    assert_includes(
      event.verification_error,
      "environment is invalid"
    )
  end

  test "processed event is idempotent" do
    event =
      create_event

    calls = 0

    verifier =
      lambda do |event:|
        calls += 1
        valid_result
      end

    verify(
      event,
      verifier
    )

    verify(
      event.reload,
      verifier
    )

    assert_equal(
      1,
      calls
    )

    assert_equal(
      1,
      TeamEntitlement.count
    )
  end

  test "previously verified pending event skips verification" do
    event =
      create_event

    event.update!(
      event_type:
        "subscription_activated",
      environment:
        "sandbox",
      provider_subscription_id:
        "google-subscription-verified",
      occurred_at:
        @starts_at,
      metadata:
        valid_result.fetch(
          :metadata
        )
    )

    event.mark_verified!(
      at: @starts_at
    )

    verifier =
      lambda do |event:|
        raise "Verifier should not be called"
      end

    verify(
      event,
      verifier
    )

    assert event.reload.processed?

    assert_equal(
      "active",
      @team
        .reload
        .team_entitlement
        .status
    )
  end

  test "processing failure does not remove verified state" do
    event =
      create_event(
        team: nil
      )

    assert_raises(
      StoreSubscriptionEventProcessor::
        MissingTeam
    ) do
      verify(
        event,
        verifier_returning(
          valid_result
        )
      )
    end

    event.reload

    assert event.verified?
    assert event.failed?

    assert_includes(
      event.processing_error,
      "Could not resolve a MatchMuster team"
    )

    assert_nil(
      event.verification_error
    )
  end

  private

  def verify(event, verifier)
    StoreSubscriptionEventVerificationService.call(
      event: event,
      verifier: verifier
    )
  end

  def verifier_returning(result)
    lambda do |event:|
      result
    end
  end

  def create_event(team: @team)
    @event_sequence += 1

    StoreSubscriptionEvent.create!(
      team: team,
      provider: "google_play",
      provider_event_id:
        "verification-event-#{@event_sequence}",
      event_type:
        "notification_received",
      environment: "sandbox",
      processing_status: "pending",
      verification_status: "pending",
      metadata: {},
      raw_payload: {
        "message" => {
          "messageId" =>
            "verification-message-#{@event_sequence}",
          "data" =>
            "encoded-notification"
        }
      }
    )
  end

  def valid_result
    {
      event_type:
        "subscription_activated",

      environment:
        "sandbox",

      provider_subscription_id:
        "google-subscription-verified",

      occurred_at:
        @starts_at.iso8601,

      metadata: {
        "billing_period" =>
          "monthly",

        "product_id" =>
          "matchmuster_plus",

        "base_plan_id" =>
          "monthly",

        "starts_at" =>
          @starts_at.iso8601,

        "ends_at" =>
          @ends_at.iso8601,

        "auto_renews" =>
          true
      }
    }
  end
end
