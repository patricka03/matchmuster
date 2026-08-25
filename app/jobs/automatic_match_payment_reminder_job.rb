class AutomaticMatchPaymentReminderJob <
  ApplicationJob

  queue_as :default

  retry_on ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError,
           wait: :polynomially_longer,
           attempts: 5

  def perform(match_payment_id)
    match_payment =
      MatchPayment
        .includes(
          :user,
          match: :team
        )
        .find_by(
          id: match_payment_id
        )

    return unless match_payment
    return unless match_payment.status == "pending"

    match =
      match_payment.match

    return if match.cancelled_at.present?
    return if match.kickoff_time <= Time.current

    return unless
      PlusAccess.allowed?(
        team: match.team,
        feature:
          :automatic_payment_reminders
      )

    Notification.create_once!(
      user: match_payment.user,

      deduplication_key:
        "match_payment:#{match_payment.id}:" \
        "automatic_reminder",

      team: match.team,
      match: match,
      match_payment: match_payment,

      title:
        "Match payment reminder",

      message:
        payment_message(
          match_payment
        ),

      notification_type:
        "match_payment_reminder"
    )
  end

  private

  def payment_message(match_payment)
    amount =
      format(
        "£%.2f",
        match_payment.amount_pence /
          100.0
      )

    "Your #{amount} match payment for the " \
      "fixture against " \
      "#{match_payment.match.opponent} " \
      "is still outstanding."
  end
end
