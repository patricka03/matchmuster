require "test_helper"

class RecurringTrainingServiceTest <
  ActiveJob::TestCase

  setup do
    @team =
      Team.create!(
        name:
          "Recurring Training FC"
      )

    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    clear_enqueued_jobs
  end

  test "creates a grouped weekly training series" do
    trainings = nil

    travel_to(
      @now
    ) do
      assert_difference(
        "Training.count",
        3
      ) do
        trainings =
          create_series(
            frequency:
              "weekly",
            occurrences: 3
          )
      end
    end

    assert_equal(
      3,
      trainings.length
    )

    group_ids =
      trainings.map(
        &:recurrence_group_id
      ).uniq

    assert_equal(
      1,
      group_ids.length
    )

    assert_match(
      Training::RECURRENCE_GROUP_ID_FORMAT,
      group_ids.first
    )

    assert_equal(
      [
        1,
        2,
        3
      ],
      trainings.map(
        &:recurrence_sequence
      )
    )

    assert_equal(
      [
        @now + 4.days,
        @now + 11.days,
        @now + 18.days
      ],
      trainings.map(
        &:starts_at
      )
    )

    assert(
      trainings.all? do |training|
        training.recurrence_frequency ==
          "weekly"
      end
    )
  end

  test "creates a fortnightly training series" do
    trainings =
      create_series(
        frequency:
          "fortnightly",
        occurrences: 3
      )

    assert_equal(
      [
        @now + 4.days,
        @now + 18.days,
        @now + 32.days
      ],
      trainings.map(
        &:starts_at
      )
    )

    assert(
      trainings.all? do |training|
        training.recurrence_frequency ==
          "fortnightly"
      end
    )
  end

  test "rejects an unsupported frequency" do
    error =
      assert_raises(
        RecurringTrainingService::
          InvalidSchedule
      ) do
        create_series(
          frequency:
            "daily",
          occurrences: 3
        )
      end

    assert_includes(
      error.message,
      "weekly or fortnightly"
    )

    assert_equal(
      0,
      @team
        .trainings
        .count
    )
  end

  test "rejects occurrence counts outside the safe range" do
    [
      1,
      53,
      "not-a-number"
    ].each do |occurrences|
      assert_raises(
        RecurringTrainingService::
          InvalidSchedule
      ) do
        create_series(
          frequency:
            "weekly",
          occurrences:
            occurrences
        )
      end
    end

    assert_equal(
      0,
      @team
        .trainings
        .count
    )
  end

  test "invalid training details create no partial series" do
    attributes =
      valid_attributes.merge(
        location: ""
      )

    assert_no_difference(
      "Training.count"
    ) do
      error =
        assert_raises(
          RecurringTrainingService::
            InvalidSchedule
        ) do
          RecurringTrainingService.call(
            team: @team,
            attributes: attributes,
            frequency: "weekly",
            occurrences: 4
          )
        end

      assert_includes(
        error.message,
        "Location"
      )
    end
  end

  test "one-off training does not require recurrence metadata" do
    training =
      @team
        .trainings
        .create!(
          valid_attributes
        )

    assert_not(
      training.recurring?
    )

    assert_nil(
      training.recurrence_group_id
    )

    assert_nil(
      training.recurrence_sequence
    )

    assert_nil(
      training.recurrence_frequency
    )
  end

  private

  def create_series(
    frequency:,
    occurrences:
  )
    RecurringTrainingService.call(
      team: @team,
      attributes:
        valid_attributes,
      frequency: frequency,
      occurrences: occurrences
    )
  end

  def valid_attributes
    {
      title:
        "Thursday Training",
      location:
        "Training Ground",
      description:
        "Weekly first-team session",
      meet_time:
        @now +
        4.days -
        30.minutes,
      starts_at:
        @now +
        4.days
    }
  end
end
