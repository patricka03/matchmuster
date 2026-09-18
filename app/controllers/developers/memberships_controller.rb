module Developers
  class MembershipsController < BaseController
    rescue_from ArgumentError,
                with: :render_membership_error

    before_action :set_team
    before_action :set_membership,
                  except: :create

    def create
      notes =
        required_notes!

      user =
        User.find(
          membership_params[
            :user_id
          ]
        )

      role =
        membership_params[
          :role
        ].presence ||
        "player"

      status =
        membership_params[
          :status
        ].presence ||
        "approved"

      preferred_position =
        membership_params[
          :preferred_position
        ].presence ||
        "CM"

      if role == "manager"
        unless user.account_type == "manager" &&
               (
                 status != "approved" ||
                 user.manager_verification_status == "approved"
               )
          return render json: {
            error:
              "Only an approved manager account can be added as an approved team manager."
          }, status: :unprocessable_entity
        end
      end

      @membership =
        @team
          .team_memberships
          .create!(
            user: user,
            role: role,
            status: status,
            preferred_position:
              preferred_position
          )

      if @team.owner_user_id.blank? &&
         role == "manager" &&
         status == "approved"
        @team.update!(
          owner_user:
            user
        )
      end

      DeveloperPlatformAudit.record!(
        developer:
          current_developer,
        action_type:
          "membership_added",
        notes:
          notes,
        target:
          @team,
        metadata: {
          membership_id:
            @membership.id,
          user_id:
            user.id,
          role:
            role,
          status:
            status
        }
      )

      render json: {
        message:
          "Team membership added.",
        membership:
          membership_json
      }, status: :created
    end

    def update
      notes =
        required_notes!

      requested_role =
        membership_params[
          :role
        ] ||
        @membership.role

      requested_status =
        membership_params[
          :status
        ] ||
        @membership.status

      validate_role_compatibility!(
        requested_role,
        requested_status
      )

      ensure_manager_continuity!(
        role:
          requested_role,
        status:
          requested_status
      )

      was_owner =
        @team.owner_user_id ==
          @membership.user_id

      @membership.update!(
        membership_params
      )

      if was_owner &&
         !(
           @membership.role == "manager" &&
           @membership.status == "approved"
         )
        replacement_owner =
          @team
            .team_memberships
            .includes(:user)
            .where(
              role: "manager",
              status: "approved"
            )
            .where
            .not(
              id:
                @membership.id
            )
            .order(
              :created_at,
              :id
            )
            .first
            &.user

        @team.update!(
          owner_user:
            replacement_owner
        )
      end

      DeveloperPlatformAudit.record!(
        developer:
          current_developer,
        action_type:
          "membership_updated",
        notes:
          notes,
        target:
          @team,
        metadata: {
          membership_id:
            @membership.id,
          user_id:
            @membership.user_id,
          role:
            @membership.role,
          status:
            @membership.status,
          preferred_position:
            @membership.preferred_position
        }
      )

      render json: {
        message:
          "Team membership updated.",
        membership:
          membership_json
      }, status: :ok
    end

    def destroy
      notes =
        required_notes!

      ensure_manager_continuity!(
        removing: true
      )

      user_id =
        @membership.user_id

      was_owner =
        @team.owner_user_id ==
          user_id

      TeamMembership.transaction do
        @membership.destroy!

        if was_owner
          replacement_owner =
            @team
              .team_memberships
              .includes(:user)
              .where(
                role: "manager",
                status: "approved"
              )
              .order(
                :created_at,
                :id
              )
              .first
              &.user

          @team.update!(
            owner_user:
              replacement_owner
          )
        end

        DeveloperPlatformAudit.record!(
          developer:
            current_developer,
          action_type:
            "membership_removed",
          notes:
            notes,
          target:
            @team,
          metadata: {
            membership_id:
              @membership.id,
            user_id:
              user_id,
            was_owner:
              was_owner
          }
        )
      end

      render json: {
        message:
          "Team membership removed."
      }, status: :ok
    end

    private

    def set_team
      @team =
        Team.find(
          params[:team_id]
        )
    end

    def set_membership
      @membership =
        @team
          .team_memberships
          .includes(:user)
          .find(
            params[:id]
          )
    end

    def membership_params
      params
        .require(:membership)
        .permit(
          :user_id,
          :role,
          :status,
          :preferred_position
        )
    end

    def action_params
      params
        .fetch(
          :developer_action,
          {}
        )
        .permit(
          :notes
        )
    end

    def required_notes!
      notes =
        action_params[
          :notes
        ]
          .to_s
          .strip

      if notes.blank?
        raise ActionController::ParameterMissing,
              "A reason is required for developer actions."
      end

      notes
    end

    def validate_role_compatibility!(
      role,
      status
    )
      return unless
        role == "manager"

      unless @membership.user.account_type ==
             "manager"
        raise ArgumentError,
              "A player account cannot be assigned a manager membership."
      end

      if status == "approved" &&
         @membership
           .user
           .manager_verification_status !=
           "approved"
        raise ArgumentError,
              "This manager account must be approved before it can manage a team."
      end
    end

    def ensure_manager_continuity!(
      role: @membership.role,
      status: @membership.status,
      removing: false
    )
      currently_approved_manager =
        @membership.role ==
          "manager" &&
        @membership.status ==
          "approved"

      remains_approved_manager =
        !removing &&
        role == "manager" &&
        status == "approved"

      return unless
        currently_approved_manager &&
        !remains_approved_manager

      other_manager_exists =
        @team
          .team_memberships
          .where(
            role: "manager",
            status: "approved"
          )
          .where
          .not(
            id:
              @membership.id
          )
          .exists?

      return if
        other_manager_exists

      raise ArgumentError,
            "A team must keep at least one approved manager."
    end

    def render_membership_error(error)
      render json: {
        error: error.message
      }, status: :unprocessable_entity
    end

    def membership_json
      {
        id: @membership.id,
        role: @membership.role,
        status: @membership.status,
        preferred_position:
          @membership.preferred_position,
        user: {
          id:
            @membership.user.id,
          first_name:
            @membership.user.first_name,
          last_name:
            @membership.user.last_name,
          email:
            @membership.user.email
        }
      }
    end
  end
end
