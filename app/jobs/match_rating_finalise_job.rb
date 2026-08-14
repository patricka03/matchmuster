class MatchRatingFinaliseJob < ApplicationJob
  queue_as :default

  def perform(match_id, expected_kickoff_time)
    match = Match.find_by(id: match_id)

    return unless match
    return unless current_schedule?(match, expected_kickoff_time)
    return if match.ratings_finalised_at.present?
    return unless match.ratings_closed?

    match.finalise_ratings!

    send_result_notifications(match)
  end

  private

  def current_schedule?(match, expected_kickoff_time)
    match.kickoff_time.to_i ==
      Time.zone.parse(expected_kickoff_time).to_i
  end

  def send_result_notifications(match)
    winners =
      match.match_awards
           .where(
             award_type: "man_of_the_match"
           )
           .includes(:user)

    if winners.empty?
      notify_no_award(match)
      return
    end

    winner_ids =
      winners.map(&:user_id)

    winner_names =
      winners.map do |award|
        [
          award.user.first_name,
          award.user.last_name
        ].compact.join(" ")
      end

    winners.each do |award|
      Notification.create!(
        user: award.user,
        match: match,
        title: "🏆 Man of the Match!",
        message: "Congratulations! Your teammates voted you Man of the Match against #{match.opponent}.",
        notification_type: "man_of_the_match"
      )
    end

    team_users(match).each do |user|
      next if winner_ids.include?(user.id)

      Notification.create!(
        user: user,
        match: match,
        title: result_title(winner_names),
        message: result_message(
          match,
          winner_names
        ),
        notification_type: "match_rating_result"
      )
    end
  end

  def team_users(match)
    User.joins(:team_memberships)
        .where(
          team_memberships: {
            team_id: match.team_id,
            status: "approved"
          }
        )
        .distinct
  end

  def result_title(winner_names)
    if winner_names.length > 1
      "🏆 Joint Man of the Match"
    else
      "🏆 Man of the Match"
    end
  end

  def result_message(match, winner_names)
    names = winner_names.to_sentence

    if winner_names.length > 1
      "#{names} were voted joint Man of the Match against #{match.opponent}."
    else
      "#{names} was voted Man of the Match against #{match.opponent}."
    end
  end

  def notify_no_award(match)
    team_users(match).each do |user|
      Notification.create!(
        user: user,
        match: match,
        title: "Match Ratings Closed",
        message: "There were not enough completed votes to award Man of the Match against #{match.opponent}.",
        notification_type: "match_rating_result"
      )
    end
  end
end
