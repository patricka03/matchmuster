require "test_helper"

class AutomaticTrainingReminderJobTest <
  ActiveJob::TestCase

  setup do
    @team =
      Team.create!(
        name:
          "Automatic Training FC"
      )

    @player =
      User.create!(
        first_name: "Training",
        last_name: "Player",
        account_type: "player",
        email:
          "automatic-training-player@example.com",
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

  test "free team does not receive automatic training reminder" do
    travel_to(@now) do
      training =
        create_training

      assert_no_difference(
        "@player.notifications.count"
      ) do
        perform_reminder(
          training
        )
      end
    end
  end

  test "Plus trial reminds player who has not responded" do
    travel_to(@now) do
      start_plus_trial

      training =
        create_training

      assert_difference(
        "@player.notifications.count",
        1
      ) do
        perform_reminder(
          training
        )
      end

      notification =
        @player
          .notifications
          .order(created_at: :desc)
          .first

      assert_equal(
        "training_availability_reminder",
        notification.notification_type
      )

      assert_equal(
        training.id,
        notification.training_id
      )

      assert_equal(
        @team.id,
        notification.team_id
      )

      assert_equal(
        "Please confirm your availability for Tuesday Training.",
        notification.message
      )
    end
  end

  test "automatic reminder skips player who already responded" do
    travel_to(@now) do
      start_plus_trial

      training =
        create_training

      TrainingAvailability.create!(
        training: training,
        user: @player,
        status: "available"
      )

      assert_no_difference(
        "@player.notifications.count"
      ) do
        perform_reminder(
          training
        )
      end
    end
  end

  test "stale reminder does not run after training time changes" do
    travel_to(@now) do
      start_plus_trial

      training =
        create_training

      old_starts_at =
        training.starts_at.iso8601

      training.update!(
        starts_at:
          training.starts_at +
          1.day,
        meet_time:
          training.meet_time +
          1.day
      )

      assert_no_difference(
        "@player.notifications.count"
      ) do
        AutomaticTrainingReminderJob.perform_now(
          training.id,
          old_starts_at
        )
      end
    end
  end

  test "repeated reminder delivery is idempotent" do
    travel_to(@now) do
      start_plus_trial

      training =
        create_training

      assert_difference(
        "@player.notifications.count",
        1
      ) do
        2.times do
          perform_reminder(
            training
          )
        end
      end
    end
  end

  test "reminder does not run after training begins" do
    training = nil

    travel_to(@now) do
      start_plus_trial

      training =
        create_training
    end

    travel_to(
      training.starts_at +
      1.minute
    ) do
      assert_no_difference(
        "@player.notifications.count"
      ) do
        perform_reminder(
          training
        )
      end
    end
  end

  private

  def create_training
    training =
      @team.trainings.create!(
        title:
          "Tuesday Training",
        location:
          "Training Ground",
        meet_time:
          @now +
          3.days -
          30.minutes,
        starts_at:
          @now +
          3.days
      )

    clear_enqueued_jobs

    training
  end

  def start_plus_trial
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @now
    )
  end

  def perform_reminder(training)
    AutomaticTrainingReminderJob.perform_now(
      training.id,
      training.starts_at.iso8601
    )
  end
end
