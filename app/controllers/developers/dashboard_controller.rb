module Developers
  class DashboardController < BaseController
    def show
      paid_payments = MatchPayment.where(status: "paid")

      render json: {
        message: "Developer dashboard loaded successfully",
        developer: {
          id: current_developer.id,
          email: current_developer.email
        },
        overview: {
          total_users: User.count,
          total_players: User.where(account_type: "player").count,
          total_managers: User.where(account_type: "manager").count,
          pending_managers: User.where(
            account_type: "manager",
            manager_verification_status: "pending"
          ).count,
          approved_managers: User.where(
            account_type: "manager",
            manager_verification_status: "approved"
          ).count,
          total_teams: Team.count,
          total_fixtures: Match.count,
          paid_payments: paid_payments.count,
          payment_volume_pence: paid_payments.sum(:amount_pence)
        }
      }, status: :ok
    end
  end
end
