class DeveloperAccountService
  class Error < StandardError; end

  def initialize(
    user:,
    developer:,
    notes:
  )
    @user = user
    @developer = developer
    @notes = notes.to_s.strip
  end

  def suspend!
    require_notes!
    ensure_not_deleted!

    if @user.banned?
      raise Error,
            "A banned account must be reactivated before it can be suspended."
    end

    if @user.suspended?
      raise Error,
            "This account is already suspended."
    end

    User.transaction do
      @user.update!(
        suspended_at:
          Time.current,
        suspension_reason:
          @notes
      )

      record_action!(
        "user_suspended"
      )
    end

    @user
  end

  def ban!
    require_notes!
    ensure_not_deleted!

    if @user.banned?
      raise Error,
            "This account is already banned."
    end

    User.transaction do
      @user.update!(
        suspended_at: nil,
        banned_at:
          Time.current,
        suspension_reason:
          @notes
      )

      record_action!(
        "user_banned"
      )
    end

    @user
  end

  def restore!
    require_notes!
    ensure_not_deleted!

    unless @user.suspended? || @user.banned?
      raise Error,
            "This account is already active."
    end

    User.transaction do
      previous_status =
        @user.banned? ?
          "banned" :
          "suspended"

      @user.update!(
        suspended_at: nil,
        banned_at: nil,
        suspension_reason: nil
      )

      record_action!(
        "user_restored",
        metadata: {
          previous_status:
            previous_status
        }
      )
    end

    @user
  end

  def delete!(confirmation:)
    require_notes!
    ensure_not_deleted!

    unless confirmation == "DELETE"
      raise Error,
            "Type DELETE to confirm account deletion."
    end

    blocking_teams =
      sole_manager_teams

    if blocking_teams.any?
      raise Error,
            "This account is the only approved manager of: #{blocking_teams.map(&:name).join(', ')}. Add another approved manager before deleting it."
    end

    metadata = {
      original_account_type:
        @user.account_type,
      deleted_at:
        Time.current.iso8601
    }

    User.transaction do
      remove_active_personal_data!
      anonymise_user!

      record_action!(
        "user_deleted",
        metadata:
          metadata
      )
    end

    @user.avatar.purge_later if @user.avatar.attached?

    @user
  end

  private

  def require_notes!
    return if @notes.present?

    raise Error,
          "A reason is required for this account action."
  end

  def ensure_not_deleted!
    return unless @user.deleted?

    raise Error,
          "This account has already been deleted and anonymised."
  end

  def sole_manager_teams
    manager_memberships =
      @user
        .team_memberships
        .where(
          role: "manager",
          status: "approved"
        )
        .includes(:team)

    manager_memberships.filter_map do |membership|
      another_manager_exists =
        TeamMembership
          .where(
            team_id:
              membership.team_id,
            role: "manager",
            status: "approved"
          )
          .where.not(
            user_id:
              @user.id
          )
          .exists?

      membership.team unless another_manager_exists
    end
  end

  def remove_active_personal_data!
    @user.team_memberships.destroy_all
    @user.notifications.destroy_all
    @user.post_reads.destroy_all
    @user.availabilities.destroy_all
    @user.squad_selections.destroy_all
    @user.posts.destroy_all
  end

  def anonymise_user!
    deleted_email =
      "deleted-#{@user.id}-#{SecureRandom.hex(8)}@deleted.matchmuster.invalid"

    replacement_password =
      SecureRandom.hex(32)

    @user.assign_attributes(
      first_name: "Deleted",
      last_name: "User",
      email: deleted_email,
      password: replacement_password,
      password_confirmation: replacement_password,
      deleted_at: Time.current,
      suspended_at: nil,
      banned_at: nil,
      suspension_reason: nil,
      jti: SecureRandom.uuid,
      reset_password_token: nil,
      reset_password_sent_at: nil,
      remember_created_at: nil
    )

    @user.save!
  end

  def record_action!(
    action_type,
    metadata: {}
  )
    DeveloperAccountAction.create!(
      developer: @developer,
      target_user: @user,
      action_type: action_type,
      notes: @notes,
      metadata: metadata
    )
  end
end
