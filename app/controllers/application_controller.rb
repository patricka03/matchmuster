class ApplicationController < ActionController::API
  include ActionController::MimeResponds

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :enforce_user_account_access!
  before_action :enforce_multi_team_owner_access!

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

  def enforce_multi_team_owner_access!
    return unless
      current_user&.manager? &&
      current_user.manager_verification_status == "approved"

    team =
      requested_multi_team_access_team

    return unless team

    access =
      MultiTeamOwnerAccess.new(
        manager: current_user
      )

    return if access.accessible?(
      team: team
    )

    render json:
      access.denial_payload(
        team: team
      ),
      status: :forbidden
  end

  def requested_multi_team_access_team
    team_id = params[:team_id]

    if team_id.present?
      return Team.find_by(
        id: team_id
      )
    end

    if controller_name == "teams" &&
      params[:id].present?

      return Team.find_by(
        id: params[:id]
      )
    end

    if controller_name == "team_memberships" &&
      params[:id].present?

      return TeamMembership
        .includes(:team)
        .find_by(
          id: params[:id]
        )
        &.team
    end

    nil
  end

  def require_plus!(
    team:,
    feature:
  )
    return true if
      PlusAccess.allowed?(
        team: team,
        feature: feature
      )

    render json:
      PlusAccess.denial_payload(
        feature: feature
      ),
      status: :forbidden

    false
  end

  def allow_browser
    request.session_options[:skip] = true
  end
end
