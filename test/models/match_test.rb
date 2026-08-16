require "test_helper"

class MatchTest < ActiveSupport::TestCase
  test "finalising ratings creates one clear winner" do
    context = create_rating_context
    match = context[:match]
    rater = context[:rater]
    player = context[:player]

    submit_test_rating(
      match: match,
      rater: rater,
      player: player,
      rating: 7.0
    )

    submit_test_rating(
      match: match,
      rater: player,
      player: rater,
      rating: 9.0
    )

    close_rating_window(match)
    match.finalise_ratings!

    awards =
      match.match_awards.where(
        award_type: "man_of_the_match"
      )

    assert_equal 1, awards.count
    assert_equal rater, awards.first.user
    assert_equal 9.0, awards.first.average_rating.to_f
    assert match.reload.ratings_finalised_at.present?
  end

  test "finalising ratings creates joint winners" do
    context = create_rating_context
    match = context[:match]
    rater = context[:rater]
    player = context[:player]

    submit_test_rating(
      match: match,
      rater: rater,
      player: player,
      rating: 9.0
    )

    submit_test_rating(
      match: match,
      rater: player,
      player: rater,
      rating: 9.0
    )

    close_rating_window(match)
    match.finalise_ratings!

    awards =
      match
        .match_awards
        .where(
          award_type: "man_of_the_match"
        )

    assert_equal 2, awards.count

    assert_equal(
      [rater.id, player.id].sort,
      awards.pluck(:user_id).sort
    )

    assert awards.all? do |award|
      award.average_rating.to_f == 9.0
    end
  end
  test "finalising with insufficient turnout creates no award" do
    context = create_rating_context
    team = context[:team]
    match = context[:match]
    rater = context[:rater]
    player = context[:player]

    third_player =
      create_test_user(
        first_name: "Third"
      )

    select_test_player(
      team: team,
      match: match,
      player: third_player,
      position: "CB"
    )

    submit_test_rating(
      match: match,
      rater: rater,
      player: player,
      rating: 8.0
    )

    submit_test_rating(
      match: match,
      rater: rater,
      player: third_player,
      rating: 8.0
    )

    assert_equal 1, match.submitted_rating_voters
    assert_not match.enough_rating_turnout?

    close_rating_window(match)
    match.finalise_ratings!

    awards =
      match.match_awards.where(
        award_type: "man_of_the_match"
      )

    assert_empty awards
    assert match.reload.ratings_finalised_at.present?
  end
end
