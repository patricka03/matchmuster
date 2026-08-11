class UsersController < ApplicationController
  before_action :authenticate_user!

  def me
    render json: {
      user: user_json(current_user)
    }, status: :ok
  end

  def update_profile
    if current_user.update(profile_params)
      render json: {
        message: "Profile updated successfully",
        user: user_json(current_user)
      }, status: :ok
    else
      render json: {
        errors: current_user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def update_avatar
    if params[:avatar].blank?
      return render json: {
        error: "Please select an image"
      }, status: :unprocessable_entity
    end

    current_user.avatar.attach(params[:avatar])

    render json: {
      message: "Profile picture updated successfully",
      avatar_url: url_for(current_user.avatar),
      user: user_json(current_user)
    }, status: :ok
  end

  def update_password
    if current_user.update_with_password(password_params)
      current_user.update_column(:jti, SecureRandom.uuid)

      render json: {
        message: "Password updated successfully. Please log in again."
      }, status: :ok
    else
      render json: {
        errors: current_user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def user_json(user)
    {
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      account_type: user.account_type,
      manager_verification_status: user.manager_verification_status,
      preferred_position:
        user.team_memberships.find_by(role: "player")&.preferred_position,
      avatar_url:
        user.avatar.attached? ? url_for(user.avatar) : nil
    }
  end



  private

  def profile_params
    params.require(:user).permit(
      :first_name,
      :last_name,
      :email
    )
  end

  def password_params
    params.require(:user).permit(
      :current_password,
      :password,
      :password_confirmation
    )
  end
end
