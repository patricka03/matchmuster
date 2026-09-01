module Developers
  class ActivitiesController < BaseController
    def index
      limit = params.fetch(:limit, 20).to_i.clamp(1, 50)

      activities = [
        user_activities(limit),
        team_activities(limit),
        fixture_activities(limit),
        payment_activities(limit)
      ].flatten

      activities = activities
                   .sort_by { |activity| activity[:occurred_at] }
                   .reverse
                   .first(limit)

      render json: {
        message: "Recent platform activity loaded successfully",
        count: activities.count,
        activities: activities
      }, status: :ok
    end

    private

    def user_activities(limit)
      User.order(created_at: :desc).limit(limit).map do |user|
        full_name = [
          user.first_name,
          user.last_name
        ].compact.join(" ").strip

        full_name = user.email if full_name.blank?

        {
          id: "user-#{user.id}",
          activity_type: "user_registered",
          message: "#{full_name} registered as a #{user.account_type}",
          resource_type: "User",
          resource_id: user.id,
          details: {
            full_name: full_name,
            email: user.email,
            account_type: user.account_type,
            manager_verification_status: user.manager_verification_status
          },
          occurred_at: user.created_at
        }
      end
    end

    def team_activities(limit)
      Team.order(created_at: :desc).limit(limit).map do |team|
        {
          id: "team-#{team.id}",
          activity_type: "team_created",
          message: "#{team.name} was created",
          resource_type: "Team",
          resource_id: team.id,
          details: {
            name: team.name
          },
          occurred_at: team.created_at
        }
      end
    end

    def fixture_activities(limit)
      Match.order(created_at: :desc).limit(limit).map do |fixture|
        {
          id: "fixture-#{fixture.id}",
          activity_type: "fixture_created",
          message: "Fixture against #{fixture.opponent} was created",
          resource_type: "Match",
          resource_id: fixture.id,
          details: {
            opponent: fixture.opponent,
            team_id: fixture.team_id
          },
          occurred_at: fixture.created_at
        }
      end
    end

    def payment_activities(limit)
      MatchPayment
        .where(status: "paid")
        .order(updated_at: :desc)
        .limit(limit)
        .map do |payment|
          {
            id: "payment-#{payment.id}",
            activity_type: "payment_received",
            message: "A £#{format('%.2f', payment.amount_pence.to_i / 100.0)} payment was completed",
            resource_type: "MatchPayment",
            resource_id: payment.id,
            details: {
              amount_pence: payment.amount_pence,
              match_id: payment.match_id,
              team_id: payment.team_id,
              payment_type: payment.payment_type,
              status: payment.status
            },
            occurred_at: payment.updated_at
          }
        end
    end
  end
end
