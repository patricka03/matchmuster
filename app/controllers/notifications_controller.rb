class NotificationsController < ApplicationController
  before_action :authenticate_user!

  before_action :set_notification,
                only: %i[
                  update
                  destroy
                ]

  def index
    @notifications =
      current_user
        .notifications
        .includes(
          :match,
          { post: :user },
          match_payment: :match
        )
        .order(
          created_at: :desc
        )

    match_ids =
      @notifications
        .filter_map(&:match_id)
        .uniq

    availability_match_ids =
      current_user
        .availabilities
        .where(
          match_id: match_ids
        )
        .pluck(:match_id)
        .to_h do |match_id|
          [match_id, true]
        end

    render json:
      @notifications.map do |notification|
        notification
          .as_json
          .merge(
            "team_id" =>
              notification_team_id(
                notification
              ),

            "post" =>
              post_json(
                notification.post
              ),

            "availability_submitted" =>
              availability_submitted?(
                notification,
                availability_match_ids
              )
          )
      end,
      status: :ok
  end

  def update
    attributes = {}

    if notification_params[
      :opened
    ] == true
      attributes[:read] =
        true

      attributes[:opened_at] =
        @notification.opened_at ||
        Time.current
    end

    if notification_params.key?(
      :kept
    )
      attributes[:kept_at] =
        notification_params[
          :kept
        ] == true ?
          Time.current :
          nil
    end

    if @notification.update(
      attributes
    )
      render json:
        notification_json(
          @notification
        ),
        status: :ok
    else
      render json: {
        errors:
          @notification
            .errors
            .full_messages
      }, status: :unprocessable_entity
    end
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
        .find(
          params[:id]
        )
  end

  def notification_params
    params
      .require(:notification)
      .permit(
        :opened,
        :kept
      )
  end

  def notification_team_id(
    notification
  )
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

    current_user.availabilities.exists?(
      match_id:
        notification.match_id
    )
  end

  def notification_json(
    notification
  )
    notification
      .as_json
      .merge(
        "team_id" =>
          notification_team_id(
            notification
          ),

        "post" =>
          post_json(
            notification.post
          ),

        "availability_submitted" =>
          availability_submitted?(
            notification
          )
      )
  end

  def post_json(post)
    return nil unless post

    {
      id: post.id,
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
end
