require "test_helper"

class AvailabilityTest < ActiveSupport::TestCase
  test "becoming unavailable before kickoff removes player from squad" do
    context = create_rating_context
    match = context[:match]
    player = context[:rater]

    availability =
      Availability.find_by!(
        match: match,
        user: player
      )

    assert_difference(
      -> { match.squad_selections.count },
      -1
    ) do
      availability.update!(
        status: "unavailable"
      )
    end

    assert availability.removed_from_matchday_squad?

    assert_not(
      match.squad_selections.exists?(
        user: player
      )
    )
  end

  test "becoming unavailable after kickoff does not remove player" do
    context = create_rating_context
    match = context[:match]
    player = context[:rater]

    match.update_columns(
      kickoff_time: 1.hour.ago,
      updated_at: Time.current
    )

    availability =
      Availability.find_by!(
        match: match,
        user: player
      )

    assert_no_difference(
      -> { match.squad_selections.count }
    ) do
      availability.update!(
        status: "unavailable"
      )
    end

    assert_not availability.removed_from_matchday_squad?

    assert(
      match.squad_selections.exists?(
        user: player
      )
    )
  end
end
