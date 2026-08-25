require "test_helper"

class PlusAccessFeatureStatesTest <
  ActiveSupport::TestCase

  setup do
    @team =
      Team.create!(
        name:
          "Feature States FC"
      )

    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
  end

  test "free team receives every Plus feature as locked" do
    states =
      feature_states

    assert_equal(
      PlusAccess::FEATURES.count,
      states.count
    )

    assert_equal(
      PlusAccess
        .feature_keys
        .map(&:to_s)
        .sort,
      states
        .map do |state|
          state.fetch(
            :key
          )
        end
        .sort
    )

    assert(
      states.all? do |state|
        state.fetch(
          :available
        ) == false
      end
    )

    assert(
      states.all? do |state|
        state.fetch(
          :locked
        ) == true
      end
    )
  end

  test "active trial receives every Plus feature as available" do
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @now
    )

    states =
      feature_states(
        at:
          @now + 1.day
      )

    assert(
      states.all? do |state|
        state.fetch(
          :available
        ) == true
      end
    )

    assert(
      states.all? do |state|
        state.fetch(
          :locked
        ) == false
      end
    )
  end

  test "expired trial receives every Plus feature as locked" do
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @now
    )

    states =
      feature_states(
        at:
          @now + 31.days
      )

    assert(
      states.all? do |state|
        state.fetch(
          :available
        ) == false
      end
    )

    assert(
      states.all? do |state|
        state.fetch(
          :locked
        ) == true
      end
    )
  end

  test "feature state includes frontend display name" do
    manager_centre =
      feature_states.find do |state|
        state.fetch(
          :key
        ) ==
          "manager_centre"
      end

    assert manager_centre.present?

    assert_equal(
      "Manager Centre",
      manager_centre.fetch(
        :name
      )
    )
  end

  private

  def feature_states(at: @now)
    PlusAccess.feature_states(
      team: @team,
      at: at
    )
  end
end
