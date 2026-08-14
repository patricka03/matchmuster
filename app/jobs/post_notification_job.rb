class PostNotificationJob < ApplicationJob
  queue_as :default

  retry_on ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError,
           wait: :polynomially_longer,
           attempts: 5

  def perform(
    team_id:,
    post_id:,
    title:,
    message:,
    notification_type:
  )
    team =
      Team.find_by(
        id: team_id
      )

    return unless team

    post =
      Post.find_by(
        id: post_id,
        team_id: team.id
      )

    return unless post

    approved_memberships =
      team
        .team_memberships
        .includes(:user)
        .where(
          status: "approved"
        )

    approved_memberships.each do |membership|
      next if
        membership.user_id ==
        post.user_id

      Notification.create_once!(
        user:
          membership.user,

        deduplication_key:
          "post:#{post.id}:notification",

        post:
          post,

        title:
          title,

        message:
          message,

        notification_type:
          notification_type
      )
    end
  end
end
