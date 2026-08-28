require "test_helper"

class MatchEngagementNotificationJobTest < ActiveJob::TestCase
  setup do
    @now = Time.zone.parse("2026-09-01 12:00:00")
    @team = Team.create!(name: "Engagement FC")

    @manager = User.create!(
      first_name: "Manager",
      last_name: "One",
      account_type: "manager",
      email: "manager@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @manager.update!(manager_verification_status: "approved")
    TeamMembership.create!(
      team: @team,
      user: @manager,
      role: "manager",
      status: "approved",
      preferred_position: "CM"
    )

    @selected_player = create_player("selected@example.com")
    @unselected_player = create_player("unselected@example.com")

    travel_to(@now) do
      @match = @team.matches.create!(
        opponent: "Test United",
        match_type: "league",
        location: "Test Ground",
        kickoff_time: @now + 3.days
      )
    end

    clear_enqueued_jobs
  end

  test "manager receives starting XI reminder when fewer than eleven starters exist" do
    travel_to(@now) do
      assert_difference("@manager.notifications.count", 1) do
        perform_event("squad_selection_reminder")
      end
    end

    assert_equal(
      "squad_selection_reminder",
      @manager.notifications.last.notification_type
    )
  end

  test "starting XI reminder is skipped when eleven starters exist" do
    travel_to(@now) do
      11.times do |index|
        player = create_player("starter#{index}@example.com")
        Availability.create!(
          match: @match,
          user: player,
          status: "available"
        )
        SquadSelection.create!(
          match: @match,
          user: player,
          selection_type: "starter",
          position: "CM"
        )
      end

      assert_no_difference("@manager.notifications.count") do
        perform_event("squad_selection_reminder")
      end
    end
  end

  test "kickoff reminder goes to managers and selected players only" do
    travel_to(@now) do
      Availability.create!(
        match: @match,
        user: @selected_player,
        status: "available"
      )
      SquadSelection.create!(
        match: @match,
        user: @selected_player,
        selection_type: "starter",
        position: "CM"
      )

      perform_event("kickoff_reminder")
    end

    assert_equal(
      1,
      @manager.notifications.where(
        notification_type: "match_kickoff_reminder"
      ).count
    )
    assert_equal(
      1,
      @selected_player.notifications.where(
        notification_type: "match_kickoff_reminder"
      ).count
    )
    assert_equal(
      0,
      @unselected_player.notifications.where(
        notification_type: "match_kickoff_reminder"
      ).count
    )
  end

  private

  def create_player(email)
    player = User.create!(
      first_name: "Test",
      last_name: "Player",
      account_type: "player",
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!"
    )

    TeamMembership.create!(
      team: @team,
      user: player,
      role: "player",
      status: "approved",
      preferred_position: "CM"
    )

    player
  end

  def perform_event(event_type)
    MatchEngagementNotificationJob.perform_now(
      @match.id,
      @match.kickoff_time.iso8601,
      event_type
    )
  end
end
