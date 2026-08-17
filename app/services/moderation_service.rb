class ModerationService
  class Error < StandardError; end

  def initialize(
    report:,
    developer:
  )
    @report =
      report

    @developer =
      developer
  end

  def start_review!(notes: nil)
    update_report!(
      status: "reviewing",
      action_type: "review_started",
      notes: notes
    )
  end

  def dismiss!(notes:)
    require_notes!(notes)

    update_report!(
      status: "dismissed",
      action_type: "report_dismissed",
      notes: notes
    )
  end

  def remove_content!(notes:)
    require_notes!(notes)

    content =
      @report.reportable

    unless content
      raise Error,
            "The reported content is no longer available."
    end

    metadata = {
      reportable_type:
        content.class.name,

      reportable_id:
        content.id
    }

    Report.transaction do
      case content
      when Post
        content.destroy!

      when MatchRating
        if content.comment.blank?
          raise Error,
                "This rating does not contain a comment."
        end

        content.update!(
          comment: nil
        )

      else
        raise Error,
              "This content type cannot be removed."
      end

      mark_actioned!(
        notes
      )

      record_action!(
        action_type:
          "content_removed",

        notes:
          notes,

        metadata:
          metadata
      )
    end

    @report
  end

  def suspend_user!(notes:)
    require_notes!(notes)

    user =
      target_user!

    ensure_user_not_deleted!(user)

    if user.banned?
      raise Error,
            "A banned account must be reactivated before it can be suspended."
    end

    if user.suspended?
      raise Error,
            "This account is already suspended."
    end

    Report.transaction do
      user.update!(
        suspended_at:
          Time.current,

        suspension_reason:
          notes
      )

      mark_actioned!(
        notes
      )

      record_action!(
        action_type:
          "user_suspended",

        notes:
          notes,

        target_user:
          user
      )
    end

    @report
  end

  def ban_user!(notes:)
    require_notes!(notes)

    user =
      target_user!

    ensure_user_not_deleted!(user)

    if user.banned?
      raise Error,
            "This account is already banned."
    end

    Report.transaction do
      user.update!(
        suspended_at: nil,

        banned_at:
          Time.current,

        suspension_reason:
          notes
      )

      mark_actioned!(
        notes
      )

      record_action!(
        action_type:
          "user_banned",

        notes:
          notes,

        target_user:
          user
      )
    end

    @report
  end

  def restore_user!(notes:)
    require_notes!(notes)

    user =
      target_user!

    ensure_user_not_deleted!(user)

    unless user.suspended? || user.banned?
      raise Error,
            "This account is already active."
    end

    Report.transaction do
      user.update!(
        suspended_at: nil,
        banned_at: nil,
        suspension_reason: nil
      )

      @report.update!(
        reviewed_by:
          @developer,

        reviewed_at:
          Time.current,

        moderation_notes:
          notes
      )

      record_action!(
        action_type:
          "user_restored",

        notes:
          notes,

        target_user:
          user
      )
    end

    @report
  end

  def delete_user!(notes:)
    require_notes!(notes)

    user =
      target_user!

    ensure_user_not_deleted!(user)

    blocking_teams =
      sole_manager_teams(user)

    if blocking_teams.any?
      raise Error,
            "This account is the only approved manager of: #{blocking_teams.map(&:name).join(', ')}. Add another approved manager before deleting it."
    end

    metadata = {
      account_type:
        user.account_type,

      deleted_at:
        Time.current.iso8601
    }

    Report.transaction do
      remove_active_personal_data!(user)
      anonymise_user!(user)

      mark_actioned!(
        notes
      )

      record_action!(
        action_type:
          "user_deleted",

        notes:
          notes,

        target_user:
          user,

        metadata:
          metadata
      )
    end

    user.avatar.purge_later if user.avatar.attached?

    @report
  end

  private

  def update_report!(
    status:,
    action_type:,
    notes:
  )
    Report.transaction do
      @report.update!(
        status: status,

        moderation_notes:
          notes,

        reviewed_by:
          @developer,

        reviewed_at:
          Time.current
      )

      record_action!(
        action_type:
          action_type,

        notes:
          notes
      )
    end

    @report
  end

  def mark_actioned!(notes)
    @report.reload

    @report.update!(
      status: "actioned",

      moderation_notes:
        notes,

      reviewed_by:
        @developer,

      reviewed_at:
        Time.current
    )
  end

  def record_action!(
    action_type:,
    notes:,
    target_user: nil,
    metadata: {}
  )
    @report
      .moderation_actions
      .create!(
        developer:
          @developer,

        target_user:
          target_user,

        action_type:
          action_type,

        notes:
          notes,

        metadata:
          metadata
      )
  end

  def target_user!
    user =
      @report.reported_user

    unless user
      raise Error,
            "The reported user is no longer available."
    end

    user
  end

  def ensure_user_not_deleted!(user)
    return unless user.deleted?

    raise Error,
          "This account has already been deleted."
  end

  def sole_manager_teams(user)
    manager_memberships =
      user
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
            team_id: membership.team_id,
            role: "manager",
            status: "approved"
          )
          .where.not(
            user_id: user.id
          )
          .exists?

      membership.team unless another_manager_exists
    end
  end

  def remove_active_personal_data!(user)
    user.team_memberships.destroy_all
    user.notifications.destroy_all
    user.post_reads.destroy_all
    user.availabilities.destroy_all
    user.squad_selections.destroy_all
    user.posts.destroy_all
  end

  def anonymise_user!(user)
    deleted_email =
      "deleted-#{user.id}-#{SecureRandom.hex(8)}@deleted.matchmuster.invalid"

    replacement_password =
      SecureRandom.hex(32)

    user.assign_attributes(
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

    user.save!
  end

  def require_notes!(notes)
    return if
      notes
        .to_s
        .strip
        .present?

    raise Error,
          "Moderation notes are required for this action."
  end
end
