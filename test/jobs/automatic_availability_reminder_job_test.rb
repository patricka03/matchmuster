require "test_helper"

class AutomaticAvailabilityReminderJobTest < ActiveJob::TestCase
  setup do
    @team =
      Team.create!(
        name:
          "Automatic Reminder FC"
      )

    @player =
      User.create!(
        first_name: "Reminder",
        last_name: "Player",
        account_type: "player",
        email:
          "automatic-reminder-player@example.com",
        password: "Password123!",
        password_confirmation:
          "Password123!"
      )

    TeamMembership.create!(
      team: @team,
      user: @player,
      role: "player",
      status: "approved",
      preferred_position: "CM"
    )

    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
  end

  test "free team does not receive automatic availability reminders" do
    travel_to(@now) do
      match =
        create_match

      assert_no_difference(
        "@player.notifications.count"
      ) do
        AutomaticAvailabilityReminderJob.perform_now(
          match.id,
          match.kickoff_time.iso8601
        )
      end

      assert_nil(
        match
          .reload
          .availability_reminder_sent_at
      )
    end
  end

  test "plus trial automatically reminds player who has not responded" do
    travel_to(@now) do
      TeamEntitlementService.start_standard_trial!(
        team: @team,
        starts_at: @now
      )

      match =
        create_match

      assert_difference(
        "@player.notifications.count",
        1
      ) do
        AutomaticAvailabilityReminderJob.perform_now(
          match.id,
          match.kickoff_time.iso8601
        )
      end

      notification =
        @player
          .notifications
          .order(created_at: :desc)
          .first

      assert_equal(
        "availability_reminder",
        notification.notification_type
      )

      assert_equal(
        match.id,
        notification.match_id
      )

      assert(
        match
          .reload
          .availability_reminder_sent_at
          .present?
      )
    end
  end

  test "plus automatic reminder does not chase player who already responded" do
    travel_to(@now) do
      TeamEntitlementService.start_standard_trial!(
        team: @team,
        starts_at: @now
      )

      match =
        create_match

      Availability.create!(
        match: match,
        user: @player,
        status: "available"
      )

      assert_no_difference(
        "@player.notifications.count"
      ) do
        AutomaticAvailabilityReminderJob.perform_now(
          match.id,
          match.kickoff_time.iso8601
        )
      end
    end
  end

  test "stale reminder does not run after fixture kickoff changes" do
    travel_to(@now) do
      TeamEntitlementService.start_standard_trial!(
        team: @team,
        starts_at: @now
      )

      match =
        create_match

      old_kickoff_time =
        match.kickoff_time.iso8601

      match.update!(
        kickoff_time:
          match.kickoff_time +
          1.day
      )

      assert_no_difference(
        "@player.notifications.count"
      ) do
        AutomaticAvailabilityReminderJob.perform_now(
          match.id,
          old_kickoff_time
        )
      end
    end
  end

  private

  def create_match
    @team.matches.create!(
      opponent: "Reminder United",
      match_type: "league",
      location: "Hackney Marshes",
      kickoff_time:
        @now +
        7.days
    )
  end
end
