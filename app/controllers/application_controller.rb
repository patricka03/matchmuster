class ApplicationController < ActionController::API
  include ActionController::MimeResponds
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[first_name last_name account_type])
    devise_parameter_sanitizer.permit(:account_update, keys: %i[first_name last_name])
  end

  def allow_browser
    request.session_options[:skip] = true
  end
end
