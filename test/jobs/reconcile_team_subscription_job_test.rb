require "test_helper"

class ReconcileTeamSubscriptionJobTest <
  ActiveJob::TestCase

  setup do
    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @team_sequence = 0
  end

  test "dispatches Google entitlement to Google reconciler" do
    entitlement =
      activate_paid!(
        provider: "google_play"
      )

    calls = []

    google_reconciler =
      reconciler_object do |
        received_entitlement,
        received_time
      |
        calls << [
          received_entitlement,
          received_time
        ]

        :google_result
      end

    result =
      perform_job(
        entitlement,
        reconcilers: {
          "google_play" =>
            google_reconciler
        }
      )

    assert_equal(
      :google_result,
      result
    )

    assert_equal(
      [
        [
          entitlement,
          @now
        ]
      ],
      calls
    )
  end

  test "dispatches Apple entitlement to Apple reconciler" do
    entitlement =
      activate_paid!(
        provider: "apple"
      )

    calls = []

    apple_reconciler =
      reconciler_object do |
        received_entitlement,
        received_time
      |
        calls << [
          received_entitlement,
          received_time
        ]

        :apple_result
      end

    result =
      perform_job(
        entitlement,
        reconcilers: {
          "apple" =>
            apple_reconciler
        }
      )

    assert_equal(
      :apple_result,
      result
    )

    assert_equal(
      entitlement,
      calls
        .fetch(
          0
        )
        .fetch(
          0
        )
    )

    assert_equal(
      @now,
      calls
        .fetch(
          0
        )
        .fetch(
          1
        )
    )
  end

  test "expired paid entitlement can still be reconciled" do
    entitlement =
      activate_paid!(
        provider: "google_play"
      )

    TeamEntitlementService.expire!(
      team:
        entitlement.team
    )

    calls = 0

    reconciler =
      reconciler_object do |_entitlement, _time|
        calls += 1
      end

    perform_job(
      entitlement.reload,
      reconcilers: {
        "google_play" =>
          reconciler
      }
    )

    assert_equal(
      1,
      calls
    )
  end

  test "trial entitlement is skipped" do
    team =
      create_team(
        "Trial"
      )

    entitlement =
      TeamEntitlementService.start_standard_trial!(
        team: team,
        starts_at:
          @now - 1.day
      )

    result =
      perform_job(
        entitlement,
        reconcilers: {
          "google_play" =>
            failing_reconciler
        }
      )

    assert_equal(
      entitlement,
      result
    )
  end

  test "entitlement without provider identity is skipped" do
    entitlement =
      activate_paid!(
        provider: "google_play"
      )

    entitlement.update_column(
      :provider_subscription_id,
      nil
    )

    result =
      perform_job(
        entitlement.reload,
        reconcilers: {
          "google_play" =>
            failing_reconciler
        }
      )

    assert_equal(
      entitlement,
      result
    )
  end

  test "provider without reconciler is skipped" do
    entitlement =
      activate_paid!(
        provider: "apple"
      )

    result =
      perform_job(
        entitlement,
        reconcilers: {}
      )

    assert_equal(
      entitlement,
      result
    )
  end

  test "missing entitlement is safely discarded" do
    assert_nothing_raised do
      ReconcileTeamSubscriptionJob.perform_now(
        -1,
        checked_at: @now
      )
    end
  end

  test "invalid reconciliation time is rejected" do
    entitlement =
      activate_paid!(
        provider: "google_play"
      )

    error =
      assert_raises(
        ArgumentError
      ) do
        ReconcileTeamSubscriptionJob
          .new
          .perform(
            entitlement.id,
            checked_at:
              "not-a-time",
            reconcilers: {
              "google_play" =>
                failing_reconciler
            }
          )
      end

    assert_includes(
      error.message,
      "valid timestamp"
    )
  end

  private

  def perform_job(
    entitlement,
    reconcilers:
  )
    ReconcileTeamSubscriptionJob
      .new
      .perform(
        entitlement.id,
        checked_at: @now,
        reconcilers: reconcilers
      )
  end

  def reconciler_object(&block)
    reconciler =
      Object.new

    reconciler.define_singleton_method(
      :call
    ) do |entitlement:, checked_at:|
      block.call(
        entitlement,
        checked_at
      )
    end

    reconciler
  end

  def failing_reconciler
    reconciler_object do |_entitlement, _time|
      raise(
        "Entitlement should not be reconciled"
      )
    end
  end

  def activate_paid!(provider:)
    team =
      create_team(
        provider
      )

    if provider ==
       "google_play"
      TeamEntitlementService.activate_paid_plus!(
        team: team,
        provider: provider,
        provider_subscription_id:
          "job-google-token-#{team.id}",
        billing_period: "monthly",
        provider_product_id:
          "matchmuster_plus",
        provider_base_plan_id:
          "monthly",
        starts_at:
          @now - 15.days,
        ends_at:
          @now + 15.days,
        auto_renews: true
      )
    else
      TeamEntitlementService.activate_paid_plus!(
        team: team,
        provider: provider,
        provider_subscription_id:
          "job-apple-token-#{team.id}",
        billing_period: "monthly",
        provider_product_id:
          "matchmuster_plus_monthly",
        starts_at:
          @now - 15.days,
        ends_at:
          @now + 15.days,
        auto_renews: true
      )
    end
  end

  def create_team(label)
    @team_sequence += 1

    Team.create!(
      name:
        "#{label} Job Team #{@team_sequence}"
    )
  end
end
