require "test_helper"

class MatchRatingFinaliseJobTest < ActiveJob::TestCase
  test "running twice does not duplicate awards or notifications" do
    context = create_rating_context
    match = context[:match]
    winner = context[:rater]
    other_player = context[:player]

    submit_test_rating(
      match: match,
      rater: winner,
      player: other_player,
      rating: 7.0
    )

    submit_test_rating(
      match: match,
      rater: other_player,
      player: winner,
      rating: 9.0
    )

    close_rating_window(match)

    expected_kickoff_time =
      match.kickoff_time.iso8601(6)

    2.times do
      MatchRatingFinaliseJob.perform_now(
        match.id,
        expected_kickoff_time
      )
    end

    awards =
      match.match_awards.where(
        award_type: "man_of_the_match"
      )

    assert_equal 1, awards.count
    assert_equal winner, awards.first.user

    assert_equal(
      1,
      Notification.where(
        user: winner,
        match: match,
        deduplication_key:
          "match:#{match.id}:man_of_the_match"
      ).count
    )

    assert_equal(
      1,
      Notification.where(
        user: other_player,
        match: match,
        deduplication_key:
          "match:#{match.id}:rating_result"
      ).count
    )

    assert match.reload.ratings_finalised_at.present?
  end
  test "stale job does nothing after fixture is rescheduled" do
    context = create_rating_context
    match = context[:match]
    winner = context[:rater]
    other_player = context[:player]

    submit_test_rating(
      match: match,
      rater: winner,
      player: other_player,
      rating: 7.0
    )

    submit_test_rating(
      match: match,
      rater: other_player,
      player: winner,
      rating: 9.0
    )

    old_kickoff_time =
      match.kickoff_time.iso8601(6)

    match.update!(
      kickoff_time: 5.hours.ago
    )

    MatchRatingFinaliseJob.perform_now(
      match.id,
      old_kickoff_time
    )

    match.reload

    assert_nil match.ratings_finalised_at

    assert_empty(
      match.match_awards.where(
        award_type: "man_of_the_match"
      )
    )

    MatchRatingFinaliseJob.perform_now(
      match.id,
      match.kickoff_time.iso8601(6)
    )

    match.reload

    assert match.ratings_finalised_at.present?

    awards =
      match.match_awards.where(
        award_type: "man_of_the_match"
      )

    assert_equal 1, awards.count
    assert_equal winner, awards.first.user
  end
end
