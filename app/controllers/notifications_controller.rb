class NotificationsController < ApplicationController
  before_action :authenticate_user!

  before_action :set_notification, only: %i[ update destroy ]

  def index
    notifications = current_user .notifications .includes(:actor, :featured_user, :team, { match: { squad_selections: :user } }, { post: :user }, { match_payment: %i[ match user ] }).newest_first .limit(100)

    match_ids = notifications .filter_map(&:match_id).uniq

    availability_match_ids = current_user.availabilities .where(match_id: match_ids).pluck(:match_id).to_h do
      |match_id|[match_id, true]
    end

    render json:
      notifications.map { |notification|
        notification_json(
          notification,
          availability_match_ids
        )
      },
      status: :ok
  end

  def update
    attributes = {}

    if notification_params[:opened] == true
      attributes[:read] = true

      attributes[:opened_at] =
        @notification.opened_at ||
        Time.current
    end

    if notification_params.key?(:kept)
      attributes[:kept_at] =
        notification_params[:kept] == true ?
          Time.current :
          nil
    end

    if @notification.update(attributes)
      render json:
        notification_json(@notification),
        status: :ok
    else
      render json: {
        errors:
          @notification.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def mark_all_read
    opened_at = Time.current

    updated_count =
      current_user
        .notifications
        .unread
        .update_all(
          read: true,
          opened_at: opened_at,
          updated_at: opened_at
        )

    render json: {
      updated_count: updated_count,
      opened_at: opened_at
    }, status: :ok
  end

  def destroy
    @notification.destroy!

    head :no_content
  end

  private

  def set_notification
    @notification =
      current_user
        .notifications
        .find(params[:id])
  end

  def notification_params
    params
      .require(:notification)
      .permit(
        :opened,
        :kept
      )
  end

  def notification_json(
    notification,
    availability_match_ids = nil
  )
    notification
      .as_json
      .merge(
        "team_id" =>
          notification_team_id(notification),

        "requires_action" =>
          Notification::ACTIONABLE_TYPES.include?(
            notification.notification_type
          ),

        "actor" =>
          user_json(notification.actor),

        "featured_user" =>
          user_json(notification.featured_user),

        "match" =>
          match_json(notification.match),

        "post" =>
          post_json(notification.post),

        "match_payment" =>
          match_payment_json(
            notification.match_payment
          ),

        "game_squad" =>
          game_squad_json(notification),

        "availability_submitted" =>
          availability_submitted?(
            notification,
            availability_match_ids
          )
      )
  end

  def notification_team_id(notification)
    notification.team_id ||
      notification.post&.team_id ||
      notification.match&.team_id ||
      notification
        .match_payment
        &.match
        &.team_id
  end

  def availability_submitted?(
    notification,
    availability_match_ids = nil
  )
    return false unless
      notification.match_id.present?

    return false unless
      Notification::AVAILABILITY_ACTION_TYPES.include?(
        notification.notification_type
      )

    if availability_match_ids
      return availability_match_ids.key?(
        notification.match_id
      )
    end

    current_user
      .availabilities
      .exists?(
        match_id: notification.match_id
      )
  end

  def user_json(user)
    return nil unless user

    {
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      avatar_url: avatar_url(user)
    }
  end

  def avatar_url(user)
    return nil unless user.avatar.attached?

    url_for(user.avatar)
  end

  def match_json(match)
    return nil unless match

    {
      id: match.id,
      team_id: match.team_id,
      opponent: match.opponent,
      match_type: match.match_type,
      location: match.location,
      kickoff_time: match.kickoff_time,
      formation: match.formation
    }
  end

  def post_json(post)
    return nil unless post

    {
      id: post.id,
      team_id: post.team_id,
      title: post.title,
      content: post.content,
      post_type: post.post_type,
      created_at: post.created_at,
      updated_at: post.updated_at,

      author_name: [
        post.user.first_name,
        post.user.last_name
      ]
        .compact
        .join(" ")
    }
  end

  def match_payment_json(match_payment)
    return nil unless match_payment

    {
      id: match_payment.id,
      match_id: match_payment.match_id,
      user_id: match_payment.user_id,
      amount_pence: match_payment.amount_pence,
      status: match_payment.status
    }
  end

  def game_squad_json(notification)
    return nil unless
      %w[
        squad_selected
        squad_updated
      ].include?(
        notification.notification_type
      )

    return [] unless notification.match

    notification
      .match
      .squad_selections
      .map do |selection|
        {
          id: selection.id,
          user_id: selection.user_id,
          selection_type:
            selection.selection_type,
          position: selection.position,
          captain: selection.captain,

          user: {
            id: selection.user.id,
            first_name:
              selection.user.first_name,
            last_name:
              selection.user.last_name
          }
        }
      end
  end
end
