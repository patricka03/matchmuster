class MatchRatingOpenJob < ApplicationJob
  queue_as :default

  # Temporary database connection problems should
  # not permanently kill the ratings-opening job.
  retry_on ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError,
           wait: :polynomially_longer,
           attempts: 5

  def perform(
    match_id,
    expected_kickoff_time
  )
    match =
      Match.find_by(
        id: match_id
      )

    return unless match

    return unless
      current_schedule?(
        match,
        expected_kickoff_time
      )

    return unless
      match.ratings_open?

    match.rating_rater_ids.each do |user_id|
      user =
        User.find_by(
          id: user_id
        )

      next unless user

      next if
        match.ratings_submitted_by?(
          user.id
        )

      Notification.create_once!(
        user: user,

        deduplication_key:
          "match:#{match.id}:rating_open",

        match: match,

        title:
          "Player Ratings Are Open",

        message:
          "Rate the matchday squad from the match against #{match.opponent}. You have 2 hours to submit your ratings.",

        notification_type:
          "match_rating_open"
      )
    end
  end

  private

  def current_schedule?(
    match,
    expected_kickoff_time
  )
    match.kickoff_time.to_i ==
      Time.zone
        .parse(
          expected_kickoff_time
        )
        .to_i
  end
end
