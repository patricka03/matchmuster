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

  # ========================================
  # DELETE ACCOUNT
  # ========================================

  def destroy_account
    unless current_user.valid_password?(params[:current_password].to_s)
      return render json: {
        errors: ["Current password is incorrect."]
      }, status: :unprocessable_entity
    end

    owned_teams =
      MultiTeamOwnerAccess
        .new(
          manager: current_user
        )
        .owned_teams

    if owned_teams.any?
      return render json: {
        error: "You still own one or more teams.",
        code: "owned_teams_must_be_resolved",
        message:
          "Delete your owned teams or contact MatchMuster support about an ownership transfer before deleting your account.",
        teams:
          owned_teams.map(&:name)
      }, status: :conflict
    end

    blocking_teams = sole_manager_teams

    if blocking_teams.any?
      return render json: {
        error: "You are the only approved manager of one or more teams.",
        message: "Add another approved manager before deleting your account.",
        teams: blocking_teams.map(&:name)
      }, status: :conflict
    end

    user = current_user

    User.transaction do
      # Remove active/team-specific personal data
      user.team_memberships.destroy_all
      user.notifications.destroy_all
      user.post_reads.destroy_all
      user.availabilities.destroy_all
      user.squad_selections.destroy_all
      user.posts.destroy_all
      user.match_late_statuses.destroy_all
      user.conversation_participants.destroy_all
      user.sent_messages.destroy_all
      user.social_identities.destroy_all

      # Team finance entries are retained as club records.
      # The user record below is anonymised, so any retained
      # creator relationship no longer exposes personal data.

      # We intentionally preserve:
      #
      # user.match_payments
      # user.legal_acceptances
      #
      # These may need limited retention for payment,
      # legal, fraud or dispute purposes.

      deleted_email =
        "deleted-#{user.id}-#{SecureRandom.hex(8)}@deleted.matchmuster.invalid"

      replacement_password = SecureRandom.hex(32)

      user.assign_attributes(
        first_name: "Deleted",
        last_name: "User",
        email: deleted_email,
        password: replacement_password,
        password_confirmation: replacement_password,
        deleted_at: Time.current,
        jti: SecureRandom.uuid,
        reset_password_token: nil,
        reset_password_sent_at: nil,
        remember_created_at: nil
      )

      user.save!
    end

    # Remove the user's profile picture after
    # the database changes succeed.
    user.avatar.purge if user.avatar.attached?

    render json: {
      message: "Your MatchMuster account has been deleted."
    }, status: :ok

  rescue ActiveRecord::RecordInvalid => error
    Rails.logger.error(
      "Account deletion failed for user #{current_user.id}: #{error.message}"
    )

    render json: {
      error: "Unable to delete your account."
    }, status: :unprocessable_entity
  end

  private

  # ========================================
  # SOLE MANAGER CHECK
  # ========================================

  def sole_manager_teams
    manager_memberships =
      current_user.team_memberships.where(
        role: "manager",
        status: "approved"
      )

    manager_memberships.filter_map do |membership|
      another_manager_exists =
        TeamMembership.where(
          team_id: membership.team_id,
          role: "manager",
          status: "approved"
        )
        .where.not(user_id: current_user.id)
        .exists?

      membership.team unless another_manager_exists
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
