class ScheduleAutomaticPaymentRemindersJob <
  ApplicationJob

  REMINDER_WINDOW =
    24.hours

  queue_as :default

  retry_on ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError,
           wait: :polynomially_longer,
           attempts: 5

  def perform(now: Time.current)
    reminder_candidates(
      now: now
    )
      .includes(
        match: {
          team:
            :team_entitlement
        }
      )
      .find_each do |match_payment|
        next unless
          PlusAccess.allowed?(
            team:
              match_payment.match.team,
            feature:
              :automatic_payment_reminders,
            at: now
          )

        AutomaticMatchPaymentReminderJob.perform_later(
          match_payment.id
        )
      end
  end

  private

  def reminder_candidates(now:)
    window_end =
      now +
      REMINDER_WINDOW

    MatchPayment
      .joins(:match)
      .where(
        status: "pending"
      )
      .where(
        matches: {
          cancelled_at: nil,
          kickoff_time:
            now...window_end
        }
      )
  end
end
