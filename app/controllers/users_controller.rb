class UsersController < ApplicationController
  before_action :authenticate_user!

  def me
    render json: {
      user: {
        id: current_user.id,
        first_name: current_user.first_name,
        last_name: current_user.last_name,
        email: current_user.email,
        account_type: current_user.account_type,
        manager_verification_status: current_user.manager_verification_status
      }
    }, status: :ok
  end
end
