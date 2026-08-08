class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: %i[update destroy]

  def index
    @notifications = current_user.notifications.includes(:match, post: :user).order(created_at: :desc)

    render json: @notifications.map { |notification|
      notification.as_json.merge(
        "team_id" => notification.post&.team_id ||
                    notification.match&.team_id,
        "post" => post_json(notification.post)
      )
    }, status: :ok
  end

  def update
    attributes = {}

    if notification_params[:opened] == true
      attributes[:read] = true
      attributes[:opened_at] = @notification.opened_at || Time.current
    end

    if notification_params.key?(:kept)
      attributes[:kept_at] =
        notification_params[:kept] == true ? Time.current : nil
    end

    if @notification.update(attributes)
      render json: @notification, status: :ok
    else
      render json: {
        errors: @notification.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    @notification.destroy

    head :no_content
  end

  private

  # def post_params
  #   permitted = params.require(:post).permit(:title, :content, :post_type, :pinned)
  #   permitted.delete(:pinned) unless approved_manager?

  #   permitted
  # end

  def set_notification
    @notification = current_user.notifications.find(params[:id])
  end

  def notification_params
    params.require(:notification).permit(:opened, :kept)
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
      ].compact.join(" ")
    }
  end

  def create_post_notifications
    approved_memberships = @team.team_memberships.includes(:user).where(status: "approved")

    approved_memberships.each do |membership|
      next if membership.user_id == current_user.id

      Notification.create!( user: membership.user, match: @match, title: post_notification_title, message: post_notification_message, notification_type: post_notification_type)
    end
  end

  def post_notification_type
    case @post.post_type
    when "announcement"
      "announcement"
    when "tactical"
      "tactical_post"
    else
      "post_created"
    end
  end

  def post_notification_title
    case @post.post_type
    when "announcement"
      "New Team Announcement"
    when "tactical"
      "New Tactical Post"
    else
      "New Team Post"
    end
  end

  def post_notification_message
    "#{current_user.first_name} posted: #{@post.title}"
  end
end
