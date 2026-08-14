class AvailabilityDeadlineJob < ApplicationJob
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

    return unless
      deadline_reached?(
        match
      )

    responded_user_ids =
      match
        .availabilities
        .select(:user_id)

    unanswered_player_ids =
      match
        .team
        .team_memberships
        .where(
          role: "player",
          status: "approved"
        )
        .where.not(
          user_id:
            responded_user_ids
        )
        .pluck(:user_id)

    return if
      unanswered_player_ids.empty?

    rows =
      unanswered_player_ids.map do |user_id|
        {
          user_id: user_id,
          match_id: match.id,
          status: "unavailable"
        }
      end

    Availability.insert_all(
      rows,
      unique_by:
        :index_availabilities_on_match_id_and_user_id,
      record_timestamps: true
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

  def deadline_reached?(
    match
  )
    Time.current >=
      match.kickoff_time -
        2.days
  end
end
