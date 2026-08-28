require "test_helper"

class TrainingStartNotificationJobTest < ActiveJob::TestCase
  setup do
    @now = Time.zone.parse("2026-09-01 12:00:00")
    @team = Team.create!(name: "Training Push FC")

    @manager = User.create!(
      first_name: "Manager",
      last_name: "One",
      account_type: "manager",
      email: "training-manager@example.com",
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

    @available_player = create_player("available@example.com")
    @unavailable_player = create_player("unavailable@example.com")

    travel_to(@now) do
      @training = @team.trainings.create!(
        title: "Tuesday Training",
        location: "Training Ground",
        meet_time: @now + 3.hours + 30.minutes,
        starts_at: @now + 4.hours
      )
    end

    TrainingAvailability.create!(
      training: @training,
      user: @available_player,
      status: "available"
    )
    TrainingAvailability.create!(
      training: @training,
      user: @unavailable_player,
      status: "unavailable"
    )

    clear_enqueued_jobs
  end

  test "one hour reminder goes to managers and available players only" do
    travel_to(@now) do
      TrainingStartNotificationJob.perform_now(
        @training.id,
        @training.starts_at.iso8601,
        "one_hour"
      )
    end

    assert_equal(
      1,
      @manager.notifications.where(
        notification_type: "training_start_reminder"
      ).count
    )
    assert_equal(
      1,
      @available_player.notifications.where(
        notification_type: "training_start_reminder"
      ).count
    )
    assert_equal(
      0,
      @unavailable_player.notifications.where(
        notification_type: "training_start_reminder"
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
end
