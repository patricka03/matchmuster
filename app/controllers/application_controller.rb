class ApplicationController < ActionController::API
  include ActionController::MimeResponds

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :enforce_user_account_access!

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[first_name last_name account_type])
    devise_parameter_sanitizer.permit(:account_update, keys: %i[first_name last_name])
  end

  def enforce_user_account_access!
    return unless current_user&.access_restricted?

    error, code =
      if current_user.banned?
        ["This account has been banned from MatchMuster.", "account_banned"]
      elsif current_user.suspended?
        ["This account has been suspended from MatchMuster.", "account_suspended"]
      else
        ["This account is no longer available.", "account_unavailable"]
      end

    render json: {
      error: error,
      code: code
    }, status: :unauthorized
  end

  def allow_browser
    request.session_options[:skip] = true
  end
end
