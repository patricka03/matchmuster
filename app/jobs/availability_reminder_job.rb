class AvailabilityReminderJob < ApplicationJob
  queue_as :default

  retry_on ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError,
           wait: :polynomially_longer,
           attempts: 5

  def perform(match_id)
    match =
      Match.find_by(
        id: match_id
      )

    return unless match

    responded_user_ids =
      match
        .availabilities
        .select(:user_id)

    players_to_remind =
      match
        .team
        .team_memberships
        .includes(:user)
        .where(
          role: "player",
          status: "approved"
        )
        .where.not(
          user_id:
            responded_user_ids
        )

    players_to_remind.each do |membership|
      Notification.create_once!(
        user:
          membership.user,

        deduplication_key:
          "match:#{match.id}:availability_reminder",

        match:
          match,

        title:
          "Availability Reminder",

        message:
          "Please confirm your availability for the match against #{match.opponent}.",

        notification_type:
          "availability_reminder"
      )
    end

    match.update!(
      availability_reminder_sent_at:
        Time.current
    )
  end
end
