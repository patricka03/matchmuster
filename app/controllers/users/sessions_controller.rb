module Users
  class SessionsController < Devise::SessionsController
    respond_to :json

    skip_before_action :verify_signed_out_user, only: :destroy

    def create
      self.resource = warden.authenticate(
        auth_options.merge(store: false)
      )

      if resource
        render json: {
          message: "Logged in successfully.",
          user: {
            id: resource.id,
            first_name: resource.first_name,
            last_name: resource.last_name,
            email: resource.email,
            account_type: resource.account_type,
            manager_verification_status: resource.manager_verification_status
          }
        }, status: :ok
      else
        render json: {
          error: "Invalid email or password."
        }, status: :unauthorized
      end
    end

    private

    def respond_to_on_destroy(non_navigational_status: :no_content)
      head non_navigational_status
    end
  end
end
