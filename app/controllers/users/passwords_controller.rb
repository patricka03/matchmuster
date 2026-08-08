module Users
  class PasswordsController < Devise::PasswordsController
    respond_to :json

    def create
      self.resource = resource_class.send_reset_password_instructions(resource_params)

      if successfully_sent?(resource)
        render json: {
          message: "Password reset instructions sent successfully."
        }, status: :ok
      else
        render json: {
          errors: resource.errors.full_messages
        }, status: :unprocessable_entity
      end
    end
  end
end
