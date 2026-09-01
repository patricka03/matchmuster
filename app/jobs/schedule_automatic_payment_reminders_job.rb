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
        :match,
        team: :team_entitlement
      )
      .find_each do |match_payment|
        next if match_payment.match&.cancelled_at.present?

        due_at = match_payment.due_at || match_payment.match&.kickoff_time
        next unless due_at && due_at < now + REMINDER_WINDOW
        if match_payment.payment_type == "match_sub"
          next unless due_at >= now
        else
          next if due_at < now - 30.days
        end

        next unless
          PlusAccess.allowed?(
            team:
              match_payment.team,
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
    MatchPayment
      .outstanding
      .where("due_at IS NOT NULL OR match_id IS NOT NULL")
  end
end
