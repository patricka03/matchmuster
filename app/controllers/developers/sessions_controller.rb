module Developers
  class SessionsController < Devise::SessionsController
    respond_to :json

    skip_before_action :verify_signed_out_user, only: :destroy

    private

    def respond_with(developer, _options = {})
      render json: {
        message: "Developer logged in successfully",
        developer: {
          id: developer.id,
          email: developer.email
        }
      }, status: :ok
    end

    def respond_to_on_destroy(non_navigational_status: :no_content)
      head non_navigational_status
    end
  end
end
