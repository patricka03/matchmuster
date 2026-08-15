class PostNotificationJob < ApplicationJob
  queue_as :default

  retry_on ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError,
           wait: :polynomially_longer,
           attempts: 5

  def perform(
    team_id:,
    post_id:,
    updated: false,
    **_legacy_attributes
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

    if updated
      NotificationEvents.post_updated(
        post: post,
        actor: post.user
      )
    else
      NotificationEvents.post_created(
        post: post,
        actor: post.user
      )
    end
  end
end
