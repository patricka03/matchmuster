class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_notification, only: %i[update destroy]

  def index
    @notifications = current_user.notifications.order(created_at: :desc)

    render json: @notifications
  end

  def update
    if @notification.update(notification_params)
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

  def set_notification
    @notification = current_user.notifications.find(params[:id])
  end

  def notification_params
    params.require(:notification).permit(:read)
  end
end
