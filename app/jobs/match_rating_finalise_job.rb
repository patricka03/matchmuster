class MatchRatingFinaliseJob < ApplicationJob
  queue_as :default

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

    # ========================================
    # FINALISE RATINGS
    # ========================================

    unless match.ratings_finalised_at.present?
      return unless
        match.ratings_closed?

      match.finalise_ratings!

      match.reload
    end

    # Important:
    # Notifications still run even if the
    # ratings were already finalised.
    #
    # This means if Heroku crashes after
    # finalising but before sending every
    # notification, the retry can continue.
    send_result_notifications(
      match
    )
  end

  private

  # ========================================
  # SCHEDULE SAFETY
  # ========================================

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

  # ========================================
  # RESULT NOTIFICATIONS
  # ========================================

  def send_result_notifications(
    match
  )
    winners =
      match
        .match_awards
        .where(
          award_type:
            "man_of_the_match"
        )
        .includes(
          :user
        )

    if winners.empty?
      notify_no_award(
        match
      )

      return
    end

    winner_ids =
      winners.map(
        &:user_id
      )

    winner_names =
      winners.map do |award|
        [
          award.user.first_name,
          award.user.last_name
        ]
          .compact
          .join(" ")
      end

    # ========================================
    # WINNER NOTIFICATIONS
    # ========================================

    winners.each do |award|
      Notification.create_once!(
        user:
          award.user,

        deduplication_key:
          "match:#{match.id}:man_of_the_match",

        match:
          match,

        title:
          "🏆 Man of the Match!",

        message:
          "Congratulations! Your teammates voted you Man of the Match against #{match.opponent}.",

        notification_type:
          "man_of_the_match"
      )
    end

    # ========================================
    # TEAM RESULT NOTIFICATIONS
    # ========================================

    team_users(
      match
    ).each do |user|
      next if
        winner_ids.include?(
          user.id
        )

      Notification.create_once!(
        user:
          user,

        deduplication_key:
          "match:#{match.id}:rating_result",

        match:
          match,

        title:
          result_title(
            winner_names
          ),

        message:
          result_message(
            match,
            winner_names
          ),

        notification_type:
          "match_rating_result"
      )
    end
  end

  # ========================================
  # TEAM USERS
  # ========================================

  def team_users(
    match
  )
    User
      .joins(
        :team_memberships
      )
      .where(
        team_memberships: {
          team_id:
            match.team_id,

          status:
            "approved"
        }
      )
      .distinct
  end

  # ========================================
  # TITLES
  # ========================================

  def result_title(
    winner_names
  )
    if winner_names.length > 1
      "🏆 Joint Man of the Match"
    else
      "🏆 Man of the Match"
    end
  end

  # ========================================
  # RESULT MESSAGE
  # ========================================

  def result_message(
    match,
    winner_names
  )
    names =
      winner_names.to_sentence

    if winner_names.length > 1
      "#{names} were voted joint Man of the Match against #{match.opponent}."
    else
      "#{names} was voted Man of the Match against #{match.opponent}."
    end
  end

  # ========================================
  # NO MOTM
  # ========================================

  def notify_no_award(
    match
  )
    team_users(
      match
    ).each do |user|
      Notification.create_once!(
        user:
          user,

        deduplication_key:
          "match:#{match.id}:rating_result",

        match:
          match,

        title:
          "Match Ratings Closed",

        message:
          "There were not enough completed votes to award Man of the Match against #{match.opponent}.",

        notification_type:
          "match_rating_result"
      )
    end
  end
end
