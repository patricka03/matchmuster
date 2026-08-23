class AutomaticAvailabilityReminderJob < ApplicationJob
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
      PlusAccess.allowed?(
        team: match.team,
        feature:
          :automatic_availability_reminders
      )

    return if
      availability_deadline_reached?(
        match
      )

    AvailabilityReminderJob.perform_now(
      match.id
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

  def availability_deadline_reached?(
    match
  )
    Time.current >=
      match.kickoff_time -
      2.days
  end
end
