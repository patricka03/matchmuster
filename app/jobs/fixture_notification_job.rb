class FixtureNotificationJob < ApplicationJob
  queue_as :default

  retry_on ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError,
           wait: :polynomially_longer,
           attempts: 5

  def perform(
    team_id:,
    title:,
    message:,
    notification_type:,
    deduplication_key:,
    match_id: nil,
    actor_id: nil
  )
    team =
      Team.find_by(
        id: team_id
      )

    return unless team

    match =
      if match_id.present?
        Match.find_by(id: match_id)
      end

    actor =
      if actor_id.present?
        User.find_by(id: actor_id)
      end

    approved_player_memberships =
      team
        .team_memberships
        .includes(:user)
        .where(
          role: "player",
          status: "approved"
        )

    approved_player_memberships.each do |membership|
      Notification.create_once!(
        user: membership.user,

        deduplication_key:
          deduplication_key,

        actor: actor,
        team: team,
        match: match,

        title: title,
        message: message,

        notification_type:
          notification_type
      )
    end
  end
end
