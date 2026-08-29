module Developers
  class LaunchClubsController <
    BaseController

    LAUNCH_CLUB_TARGET =
      20

    MAX_RESULTS =
      100

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
            :name,
            :id
          )

      query =
        params[
          :query
        ]
          .to_s
          .strip

      if query.present?
        escaped_query =
          ActiveRecord::Base
            .sanitize_sql_like(
              query.downcase
            )

        search =
          "%#{escaped_query}%"

        teams =
          teams.where(
            "LOWER(teams.name) LIKE :search OR " \
            "LOWER(teams.invite_code) LIKE :search",
            search: search
          )
      end

      render json: {
        launch_club_target:
          LAUNCH_CLUB_TARGET,

        launch_club_count:
          Team
            .where
            .not(
              launch_club_since:
                nil
            )
            .count,

        launch_plus_days:
          TeamEntitlementService::
            FOUNDER_PLUS_LENGTH
            .in_days
            .to_i,

        teams:
          teams
            .limit(
              MAX_RESULTS
            )
            .map do |team|
              team_response(
                team
              )
            end
      }, status: :ok
    end

    def grant
      team =
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

      LaunchClubService.grant!(
        team: team
      )

      team.reload

      render json: {
        message:
          "Launch Club granted successfully.",

        launch_club_count:
          Team
            .where
            .not(
              launch_club_since:
                nil
            )
            .count,

        team:
          team_response(
            team
          )
      }, status: :ok

    rescue ActiveRecord::RecordNotFound
      render json: {
        error:
          "Team not found"
      }, status: :not_found
    end

    private

    def team_response(team)
      owner =
        team.canonical_owner

      {
        id:
          team.id,

        name:
          team.name,

        invite_code:
          team.invite_code,

        launch_club:
          team.launch_club?,

        launch_club_since:
          team.launch_club_since,

        owner:
          owner && {
            id:
              owner.id,

            name:
              [
                owner.first_name,
                owner.last_name
              ]
                .compact
                .join(" ")
                .strip
                .presence ||
              owner.email,

            email:
              owner.email
          },

        subscription:
          TeamSubscriptionResponse
            .call(
              team: team
            )
      }
    end
  end
end
