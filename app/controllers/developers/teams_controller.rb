module Developers
  class TeamsController < BaseController
    MAX_RESULTS = 200

    before_action :set_team,
                  only: %i[
                    show
                    update
                    destroy
                    regenerate_invite_code
                    transfer_owner
                    grant_plus
                    extend_plus
                    revoke_plus
                    grant_founder
                    revoke_founder
                    reconcile_subscription
                  ]

    def index
      teams =
        Team
          .includes(
            :team_entitlement,
            :owner_user,
            team_memberships:
              :user
          )
          .order(
            created_at: :desc
          )

      query =
        params[:query]
          .to_s
          .strip
          .downcase

      if query.present?
        escaped =
          ActiveRecord::Base
            .sanitize_sql_like(
              query
            )

        pattern =
          "%#{escaped}%"

        teams =
          teams.where(
            "LOWER(teams.name) LIKE :query OR LOWER(teams.invite_code) LIKE :query",
            query: pattern
          )
      end

      if params[:plan].present?
        requested_plan =
          params[:plan].to_s

        unless %w[
          free
          plus
          paid
          complimentary
          founder
        ].include?(
          requested_plan
        )
          return render json: {
            error:
              "Invalid team plan filter."
          }, status: :unprocessable_entity
        end

        teams =
          teams.select do |team|
            subscription =
              TeamSubscriptionResponse.call(
                team: team
              )

            case requested_plan
            when "free"
              !subscription[:plus_active]
            when "plus"
              subscription[:plus_active]
            when "paid"
              subscription[:plus_active] &&
                %w[
                  apple
                  google_play
                ].include?(
                  subscription[:source]
                )
            when "complimentary"
              subscription[:plus_active] &&
                %w[
                  admin
                  founder
                  standard_trial
                ].include?(
                  subscription[:source]
                )
            when "founder"
              team.launch_club?
            end
          end
      end

      teams =
        teams.first(
          MAX_RESULTS
        ) if teams.is_a?(Array)

      teams =
        teams.limit(
          MAX_RESULTS
        ) unless teams.is_a?(Array)

      render json: {
        teams:
          teams.map do |team|
            team_json(
              team,
              detailed: false
            )
          end,
        summary:
          team_summary
      }, status: :ok
    end

    def create
      notes =
        create_params[
          :notes
        ]
          .to_s
          .strip

      if notes.blank?
        return render json: {
          error:
            "A reason is required for developer actions."
        }, status: :unprocessable_entity
      end

      owner =
        User.find(
          create_params[
            :owner_user_id
          ]
        )

      unless owner.account_type == "manager" &&
             owner.manager_verification_status == "approved"
        return render json: {
          error:
            "The team owner must be an approved manager account."
        }, status: :unprocessable_entity
      end

      team = nil

      Team.transaction do
        team =
          Team.create!(
            name:
              create_params[
                :name
              ],
            description:
              create_params[
                :description
              ],
            owner_user:
              owner
          )

        TeamMembership.create!(
          team: team,
          user: owner,
          role: "manager",
          status: "approved",
          preferred_position: "CM"
        )

        DeveloperPlatformAudit.record!(
          developer:
            current_developer,
          action_type:
            "team_created",
          notes:
            notes,
          target:
            team,
          metadata: {
            owner_user_id:
              owner.id
          }
        )
      end

      render json: {
        message:
          "Team created successfully.",
        team:
          team_json(
            team,
            detailed: true
          )
      }, status: :created
    end

    def show
      render json: {
        team:
          team_json(
            @team,
            detailed: true
          )
      }, status: :ok
    end

    def update
      notes =
        required_notes!

      @team.update!(
        team_params
      )

      audit!(
        "team_updated",
        notes: notes,
        metadata: {
          changed_fields:
            team_params.to_h.keys
        }
      )

      render_team(
        "Team updated successfully."
      )
    end

    def destroy
      notes =
        required_notes!

      unless action_params[
        :confirmation
      ] == "DELETE TEAM"
        return render json: {
          error:
            "Type DELETE TEAM to permanently remove this team."
        }, status: :unprocessable_entity
      end

      entitlement =
        @team.team_entitlement

      if entitlement&.paid? &&
         entitlement.plus_active?
        return render json: {
          error:
            "This team has an active paid store subscription. Reconcile or cancel the store subscription before deleting the team."
        }, status: :conflict
      end

      metadata = {
        team_id: @team.id,
        team_name: @team.name,
        invite_code:
          @team.invite_code,
        member_count:
          @team.team_memberships.count
      }

      Team.transaction do
        audit!(
          "team_deleted",
          notes: notes,
          metadata:
            metadata
        )

        @team.destroy!
      end

      render json: {
        message:
          "Team permanently deleted.",
        deleted_team:
          metadata
      }, status: :ok
    end

    def regenerate_invite_code
      notes =
        required_notes!

      previous_code =
        @team.invite_code

      @team.update!(
        invite_code:
          generate_invite_code
      )

      audit!(
        "team_invite_regenerated",
        notes: notes,
        metadata: {
          previous_invite_code:
            previous_code,
          new_invite_code:
            @team.invite_code
        }
      )

      render_team(
        "Invite code regenerated."
      )
    end

    def transfer_owner
      notes =
        required_notes!

      new_owner =
        User.find(
          action_params[
            :user_id
          ]
        )

      membership =
        @team
          .team_memberships
          .find_by(
            user_id:
              new_owner.id,
            role: "manager",
            status: "approved"
          )

      unless membership
        return render json: {
          error:
            "The new owner must already be an approved manager of this team."
        }, status: :unprocessable_entity
      end

      previous_owner =
        @team.canonical_owner

      @team.update!(
        owner_user:
          new_owner
      )

      audit!(
        "team_owner_transferred",
        notes: notes,
        metadata: {
          previous_owner_id:
            previous_owner&.id,
          new_owner_id:
            new_owner.id
        }
      )

      render_team(
        "Team ownership transferred."
      )
    end

    def grant_plus
      notes =
        required_notes!

      days =
        Integer(
          action_params[
            :days
          ].presence || 30
        )

      entitlement =
        TeamEntitlementService
          .grant_admin_plus!(
            team: @team,
            days: days
          )

      audit!(
        "plus_granted",
        notes: notes,
        metadata: {
          days: days,
          ends_at:
            entitlement.ends_at
        }
      )

      render_team(
        "Admin Plus granted."
      )
    rescue ArgumentError => error
      render json: {
        error: error.message
      }, status: :unprocessable_entity
    end

    def extend_plus
      notes =
        required_notes!

      days =
        Integer(
          action_params[
            :days
          ]
        )

      entitlement =
        TeamEntitlementService
          .extend_complimentary_plus!(
            team: @team,
            days: days
          )

      audit!(
        "plus_extended",
        notes: notes,
        metadata: {
          days: days,
          ends_at:
            entitlement.ends_at
        }
      )

      render_team(
        "Plus access extended."
      )
    rescue ArgumentError, TypeError => error
      render json: {
        error: error.message
      }, status: :unprocessable_entity
    end

    def revoke_plus
      notes =
        required_notes!

      entitlement =
        TeamEntitlementService
          .revoke_complimentary_plus!(
            team: @team
          )

      audit!(
        "plus_revoked",
        notes: notes,
        metadata: {
          previous_source:
            entitlement&.source
        }
      )

      render_team(
        "Complimentary Plus access revoked."
      )
    rescue ArgumentError => error
      render json: {
        error: error.message
      }, status: :unprocessable_entity
    end

    def grant_founder
      notes =
        required_notes!

      entitlement =
        LaunchClubService.grant!(
          team: @team
        )

      audit!(
        "founder_granted",
        notes: notes,
        metadata: {
          entitlement_source:
            entitlement&.source,
          ends_at:
            entitlement&.ends_at
        }
      )

      render_team(
        "Founder Club status granted."
      )
    end

    def revoke_founder
      notes =
        required_notes!

      entitlement =
        @team.team_entitlement

      Team.transaction do
        @team.update!(
          launch_club_since: nil
        )

        if entitlement&.source ==
           "founder"
          TeamEntitlementService
            .revoke_complimentary_plus!(
              team: @team
            )
        end
      end

      audit!(
        "founder_revoked",
        notes: notes,
        metadata: {
          founder_entitlement_revoked:
            entitlement&.source ==
              "founder"
        }
      )

      render_team(
        "Founder Club status removed."
      )
    rescue ArgumentError => error
      render json: {
        error: error.message
      }, status: :unprocessable_entity
    end

    def reconcile_subscription
      notes =
        required_notes!

      entitlement =
        @team.team_entitlement

      unless entitlement&.paid?
        return render json: {
          error:
            "This team does not have a paid Apple or Google Play entitlement to reconcile."
        }, status: :unprocessable_entity
      end

      ReconcileTeamSubscriptionJob
        .perform_later(
          entitlement.id
        )

      audit!(
        "subscription_reconcile_requested",
        notes: notes,
        metadata: {
          provider:
            entitlement.provider,
          provider_subscription_id:
            entitlement.provider_subscription_id
        }
      )

      render json: {
        message:
          "Subscription reconciliation queued.",
        team:
          team_json(
            @team,
            detailed: true
          )
      }, status: :accepted
    end

    private

    def set_team
      @team =
        Team
          .includes(
            :team_entitlement,
            :owner_user,
            team_memberships:
              :user
          )
          .find(
            params[:id]
          )
    end

    def create_params
      params
        .require(:team)
        .permit(
          :name,
          :description,
          :owner_user_id,
          :notes
        )
    end

    def team_params
      params
        .require(:team)
        .permit(
          :name,
          :description
        )
    end

    def action_params
      params
        .fetch(
          :developer_action,
          {}
        )
        .permit(
          :notes,
          :confirmation,
          :user_id,
          :days
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

    def audit!(
      action_type,
      notes:,
      metadata: {}
    )
      DeveloperPlatformAudit.record!(
        developer:
          current_developer,
        action_type:
          action_type,
        notes:
          notes,
        target:
          @team,
        metadata:
          metadata
      )
    end

    def render_team(message)
      @team.reload

      render json: {
        message: message,
        team:
          team_json(
            @team,
            detailed: true
          )
      }, status: :ok
    end

    def team_json(
      team,
      detailed:
    )
      owner =
        team.canonical_owner

      response = {
        id: team.id,
        name: team.name,
        description:
          team.description,
        invite_code:
          team.invite_code,
        created_at:
          team.created_at,
        updated_at:
          team.updated_at,
        launch_club:
          team.launch_club?,
        launch_club_since:
          team.launch_club_since,
        owner:
          user_summary(
            owner
          ),
        member_count:
          team
            .team_memberships
            .count,
        approved_manager_count:
          team
            .team_memberships
            .count do |membership|
              membership.role ==
                "manager" &&
                membership.status ==
                  "approved"
            end,
        approved_player_count:
          team
            .team_memberships
            .count do |membership|
              membership.role ==
                "player" &&
                membership.status ==
                  "approved"
            end,
        subscription:
          TeamSubscriptionResponse
            .call(
              team: team
            )
      }

      if detailed
        response.merge!(
          fixtures_count:
            team.matches.count,
          trainings_count:
            team.trainings.count,
          posts_count:
            team.posts.count,
          conversations_count:
            team.conversations.count,
          payments_count:
            team.match_payments.count,
          memberships:
            team
              .team_memberships
              .sort_by(&:created_at)
              .map do |membership|
                {
                  id:
                    membership.id,
                  role:
                    membership.role,
                  status:
                    membership.status,
                  preferred_position:
                    membership.preferred_position,
                  created_at:
                    membership.created_at,
                  user:
                    user_summary(
                      membership.user
                    )
                }
              end
        )
      end

      response
    end

    def user_summary(user)
      return nil unless user

      {
        id: user.id,
        first_name:
          user.first_name,
        last_name:
          user.last_name,
        email: user.email,
        account_type:
          user.account_type,
        manager_verification_status:
          user.manager_verification_status
      }
    end

    def team_summary
      subscriptions =
        Team
          .includes(
            :team_entitlement
          )
          .map do |team|
            TeamSubscriptionResponse
              .call(
                team: team
              )
          end

      {
        total:
          Team.count,
        plus:
          subscriptions.count do |subscription|
            subscription[
              :plus_active
            ]
          end,
        free:
          subscriptions.count do |subscription|
            !subscription[
              :plus_active
            ]
          end,
        paid:
          subscriptions.count do |subscription|
            subscription[
              :plus_active
            ] &&
              %w[
                apple
                google_play
              ].include?(
                subscription[
                  :source
                ]
              )
          end,
        founder:
          Team
            .where
            .not(
              launch_club_since:
                nil
            )
            .count
      }
    end

    def generate_invite_code
      loop do
        code =
          SecureRandom
            .hex(4)
            .upcase

        return code unless
          Team.exists?(
            invite_code:
              code
          )
      end
    end
  end
end
