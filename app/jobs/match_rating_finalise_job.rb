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

    unless match.ratings_finalised_at.present?
      return unless
        match.ratings_closed?

      match.finalise_ratings!

      match.reload
    end

    send_result_notifications(
      match
    )
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
        display_name(
          award.user
        )
      end

    primary_winner =
      winners.first.user

    winners.each do |award|
      NotificationDelivery.to_user_once(
        user: award.user,

        deduplication_key:
          "match:#{match.id}:man_of_the_match",

        featured_user: award.user,
        team: match.team,
        match: match,

        title:
          winner_title(
            winner_names
          ),

        message:
          winner_message(
            match,
            winner_names
          ),

        notification_type:
          "motm_announced"
      )
    end

    team_users(
      match
    ).each do |user|
      next if
        winner_ids.include?(
          user.id
        )

      NotificationDelivery.to_user_once(
        user: user,

        deduplication_key:
          "match:#{match.id}:rating_result",

        featured_user: primary_winner,
        team: match.team,
        match: match,

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
          "motm_announced"
      )
    end
  end

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

  def winner_title(
    winner_names
  )
    if winner_names.length > 1
      "🏆 Joint Player of the Match!"
    else
      "🏆 Player of the Match!"
    end
  end

  def winner_message(
    match,
    winner_names
  )
    if winner_names.length > 1
      "Congratulations! You were voted joint Player of the Match against #{match.opponent}."
    else
      "Congratulations! Your teammates voted you Player of the Match against #{match.opponent}."
    end
  end

  def result_title(
    winner_names
  )
    if winner_names.length > 1
      "🏆 Joint Player of the Match"
    else
      "🏆 Player of the Match"
    end
  end

  def result_message(
    match,
    winner_names
  )
    names =
      winner_names.to_sentence

    if winner_names.length > 1
      "#{names} were voted joint Player of the Match against #{match.opponent}."
    else
      "#{names} was voted Player of the Match against #{match.opponent}."
    end
  end

  def notify_no_award(
    match
  )
    team_users(
      match
    ).each do |user|
      NotificationDelivery.to_user_once(
        user: user,

        deduplication_key:
          "match:#{match.id}:rating_result",

        team: match.team,
        match: match,

        title:
          "Match Ratings Closed",

        message:
          "There were not enough completed votes to award Player of the Match against #{match.opponent}.",

        notification_type:
          "match_rating_result"
      )
    end
  end

  def display_name(user)
    user.first_name.to_s.strip.presence ||
      user.email
  end
end
