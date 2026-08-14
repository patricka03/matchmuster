class MatchRatingReminderJob < ApplicationJob
  queue_as :default

  def perform(match_id, expected_kickoff_time)
    match = Match.find_by(id: match_id)

    return unless match
    return unless current_schedule?(match, expected_kickoff_time)
    return unless match.ratings_open?

    match.rating_rater_ids.each do |user_id|
      next if match.ratings_submitted_by?(user_id)

      user = User.find_by(id: user_id)

      next unless user

      Notification.create!(
        user: user,
        match: match,
        title: "Ratings Reminder",
        message: "Don't forget to submit your player ratings for the match against #{match.opponent} before voting closes.",
        notification_type: "match_rating_reminder"
      )
    end
  end

  private

  def current_schedule?(match, expected_kickoff_time)
    match.kickoff_time.to_i ==
      Time.zone.parse(expected_kickoff_time).to_i
  end
end
