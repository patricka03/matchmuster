require "test_helper"

class TrainingAutomaticReminderTest <
  ActiveJob::TestCase

  setup do
    @team =
      Team.create!(
        name:
          "Training Scheduler FC"
      )

    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    clear_enqueued_jobs
  end

  test "new training schedules automatic reminder" do
    travel_to(@now) do
      training = nil

      assert_enqueued_jobs(
        1,
        only:
          AutomaticTrainingReminderJob
      ) do
        training =
          create_training
      end

      reminder_job =
        enqueued_jobs.find do |job|
          job.fetch(
            :job
          ) ==
            AutomaticTrainingReminderJob
        end

      assert reminder_job.present?

      assert_equal(
        [
          training.id,
          training.starts_at.iso8601
        ],
        reminder_job.fetch(
          :args
        )
      )
    end
  end

  test "changing training time schedules replacement reminder" do
    travel_to(@now) do
      training =
        create_training

      clear_enqueued_jobs

      new_starts_at =
        training.starts_at +
        1.day

      assert_enqueued_with(
        job:
          AutomaticTrainingReminderJob,
        args: [
          training.id,
          new_starts_at.iso8601
        ]
      ) do
        training.update!(
          starts_at:
            new_starts_at,
          meet_time:
            training.meet_time +
            1.day
        )
      end
    end
  end

  test "updating other details does not schedule replacement reminder" do
    travel_to(@now) do
      training =
        create_training

      clear_enqueued_jobs

      assert_no_enqueued_jobs(
        only:
          AutomaticTrainingReminderJob
      ) do
        training.update!(
          location:
            "New Training Ground"
        )
      end
    end
  end

  private

  def create_training
    @team.trainings.create!(
      title:
        "Thursday Training",
      location:
        "Training Ground",
      meet_time:
        @now +
        4.days -
        30.minutes,
      starts_at:
        @now +
        4.days
    )
  end
end
