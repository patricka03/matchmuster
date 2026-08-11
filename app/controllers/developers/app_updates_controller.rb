module Developers
  class AppUpdatesController < BaseController
    def create
      title = app_update_params[:title].to_s.strip
      message = app_update_params[:message].to_s.strip

      if title.blank? || message.blank?
        return render json: {
          errors: ["Title and message are required"]
        }, status: :unprocessable_entity
      end

      recipient_count = Notification.broadcast_app_update!(
        title: title,
        message: message
      )

      render json: {
        message: "App update sent successfully",
        app_update: {
          title: title,
          message: message,
          recipient_count: recipient_count,
          sent_at: Time.current
        }
      }, status: :created
    end

    private

    def app_update_params
      params.require(:app_update).permit(:title, :message)
    end
  end
end
