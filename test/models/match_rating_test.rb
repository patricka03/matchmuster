require "test_helper"

class MatchRatingTest < ActiveSupport::TestCase
  test "a user cannot rate themselves" do
    rating =
      MatchRating.new(
        rater_id: 1,
        player_id: 1
      )

    rating.validate

    assert_includes(
      rating.errors[:player],
      "cannot be the same as the rater"
    )
  end

  test "a user cannot rate the same player twice" do
    context = create_rating_context

    MatchRating.create!(
      match: context[:match],
      rater: context[:rater],
      player: context[:player],
      rating: 8.0
    )

    duplicate =
      MatchRating.new(
        match: context[:match],
        rater: context[:rater],
        player: context[:player],
        rating: 9.0
      )

    assert_not duplicate.valid?

    assert_includes(
      duplicate.errors[:player_id],
      "has already been rated by this user for this match"
    )
  end
end
