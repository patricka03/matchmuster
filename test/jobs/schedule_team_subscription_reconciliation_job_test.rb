require "test_helper"

class ScheduleTeamSubscriptionReconciliationJobTest <
  ActiveJob::TestCase

  class RecordingJob
    class << self
      attr_accessor :calls

      def perform_later(
        entitlement_id,
        checked_at:
      )
        self.calls ||= []

        calls << {
          entitlement_id:
            entitlement_id,
          checked_at:
            checked_at
        }
      end
    end
  end

  setup do
    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @team_sequence = 0

    RecordingJob.calls = []
  end

  test "schedules active Google and Apple subscriptions" do
    google =
      activate_paid!(
        provider: "google_play",
        status: "active"
      )

    apple =
      activate_paid!(
        provider: "apple",
        status: "active"
      )

    perform_schedule

    assert_equal(
      [
        google.id,
        apple.id
      ].sort,
      scheduled_ids.sort
    )

    assert(
      RecordingJob.calls.all? do |call|
        call.fetch(
          :checked_at
        ) ==
          @now
      end
    )
  end

  test "schedules cancelled and grace-period subscriptions" do
    cancelled =
      activate_paid!(
        provider: "google_play",
        status: "cancelled"
      )

    grace_period =
      activate_paid!(
        provider: "apple",
        status: "grace_period"
      )

    perform_schedule

    assert_equal(
      [
        cancelled.id,
        grace_period.id
      ].sort,
      scheduled_ids.sort
    )
  end

  test "schedules recently expired paid subscription" do
    recently_expired =
      activate_paid!(
        provider: "google_play",
        status: "expired",
        ends_at:
          @now - 2.days
      )

    perform_schedule

    assert_equal(
      [
        recently_expired.id
      ],
      scheduled_ids
    )
  end

  test "does not schedule old expired subscription" do
    activate_paid!(
      provider: "apple",
      status: "expired",
      ends_at:
        @now - 8.days
    )

    perform_schedule

    assert_empty(
      RecordingJob.calls
    )
  end

  test "does not schedule trials or founder access" do
    trial_team =
      create_team(
        "Trial"
      )

    founder_team =
      create_team(
        "Founder"
      )

    TeamEntitlementService.start_standard_trial!(
      team: trial_team,
      starts_at:
        @now - 1.day
    )

    TeamEntitlementService.grant_founder_plus!(
      team: founder_team,
      starts_at:
        @now - 1.day
    )

    perform_schedule

    assert_empty(
      RecordingJob.calls
    )
  end

  test "does not schedule paid record without subscription ID" do
    entitlement =
      activate_paid!(
        provider: "google_play",
        status: "active"
      )

    entitlement.update_column(
      :provider_subscription_id,
      nil
    )

    perform_schedule

    assert_empty(
      RecordingJob.calls
    )
  end

  test "schedules every eligible entitlement once" do
    3.times do |index|
      activate_paid!(
        provider:
          index.even? ?
            "google_play" :
            "apple",
        status: "active"
      )
    end

    perform_schedule

    assert_equal(
      3,
      scheduled_ids.length
    )

    assert_equal(
      scheduled_ids.uniq,
      scheduled_ids
    )
  end

  test "invalid schedule timestamp is rejected" do
    error =
      assert_raises(
        ArgumentError
      ) do
        ScheduleTeamSubscriptionReconciliationJob
          .new
          .perform(
            at:
              "not-a-time",
            reconciliation_job:
              RecordingJob
          )
      end

    assert_includes(
      error.message,
      "valid timestamp"
    )

    assert_empty(
      RecordingJob.calls
    )
  end

  private

  def perform_schedule
    ScheduleTeamSubscriptionReconciliationJob
      .new
      .perform(
        at: @now,
        reconciliation_job:
          RecordingJob
      )
  end

  def scheduled_ids
    RecordingJob.calls.map do |call|
      call.fetch(
        :entitlement_id
      )
    end
  end

  def activate_paid!(
    provider:,
    status:,
    ends_at:
      @now + 15.days
  )
    team =
      create_team(
        provider
      )

    entitlement =
      if provider ==
         "google_play"
        TeamEntitlementService.activate_paid_plus!(
          team: team,
          provider: provider,
          provider_subscription_id:
            "schedule-google-#{team.id}",
          billing_period: "monthly",
          provider_product_id:
            "matchmuster_plus",
          provider_base_plan_id:
            "monthly",
          starts_at:
            @now - 15.days,
          ends_at: ends_at,
          auto_renews: true
        )
      else
        TeamEntitlementService.activate_paid_plus!(
          team: team,
          provider: provider,
          provider_subscription_id:
            "schedule-apple-#{team.id}",
          billing_period: "monthly",
          provider_product_id:
            "matchmuster_plus_monthly",
          starts_at:
            @now - 15.days,
          ends_at: ends_at,
          auto_renews: true
        )
      end

    case status
    when "cancelled"
      TeamEntitlementService.cancel_paid_plus!(
        team: team,
        access_until:
          ends_at
      )

    when "grace_period"
      TeamEntitlementService.start_grace_period!(
        team: team,
        ends_at: ends_at
      )

    when "expired"
      TeamEntitlementService.expire!(
        team: team
      )
    end

    entitlement.reload
  end

  def create_team(label)
    @team_sequence += 1

    Team.create!(
      name:
        "#{label} Schedule Team #{@team_sequence}"
    )
  end
end
