module Developers
  class ControlCenterController < BaseController
    def show
      entitlements =
        TeamEntitlement
          .includes(:team)
          .to_a

      active_plus =
        entitlements.count do |entitlement|
          entitlement.plus_active?
        end

      paid_plus =
        entitlements.count do |entitlement|
          entitlement.plus_active? &&
            entitlement.paid?
        end

      complimentary_plus =
        entitlements.count do |entitlement|
          entitlement.plus_active? &&
            !entitlement.paid?
        end

      failed_store_events =
        StoreSubscriptionEvent.where(
          "processing_status = ? OR verification_status IN (?)",
          "failed",
          %w[failed rejected]
        )

      paid_match_payments =
        MatchPayment.where(
          status: "paid"
        )

      readiness =
        subscription_readiness

      render json: {
        overview: {
          total_users: User.count,
          active_users: User.where(
            deleted_at: nil,
            suspended_at: nil,
            banned_at: nil
          ).count,
          suspended_users: User.where.not(
            suspended_at: nil
          ).where(
            deleted_at: nil
          ).count,
          banned_users: User.where.not(
            banned_at: nil
          ).where(
            deleted_at: nil
          ).count,
          deleted_users: User.where.not(
            deleted_at: nil
          ).count,
          total_players: User.where(
            account_type: "player"
          ).count,
          total_managers: User.where(
            account_type: "manager"
          ).count,
          pending_managers: User.where(
            account_type: "manager",
            manager_verification_status: "pending"
          ).count,
          approved_managers: User.where(
            account_type: "manager",
            manager_verification_status: "approved"
          ).count,
          total_teams: Team.count,
          founder_clubs: Team.where.not(
            launch_club_since: nil
          ).count,
          plus_teams: active_plus,
          paid_plus_teams: paid_plus,
          complimentary_plus_teams: complimentary_plus,
          total_fixtures: Match.count,
          total_trainings: Training.count,
          total_posts: Post.count,
          total_conversations: Conversation.count,
          total_messages: Message.count,
          paid_payments: paid_match_payments.count,
          payment_volume_pence:
            paid_match_payments.sum(
              :amount_paid_pence
            ),
          outstanding_payments:
            MatchPayment.outstanding.count,
          finance_income_pence:
            TeamFinanceEntry.income.sum(
              :amount_pence
            ),
          finance_expenses_pence:
            TeamFinanceEntry.expenses.sum(
              :amount_pence
            ),
          open_reports:
            Report.where(
              status: %w[pending reviewing]
            ).count,
          failed_store_events:
            failed_store_events.count
        },
        subscription_readiness:
          readiness,
        recent_store_errors:
          failed_store_events
            .order(
              created_at: :desc
            )
            .limit(10)
            .map do |event|
              {
                id: event.id,
                provider: event.provider,
                event_type: event.event_type,
                processing_status:
                  event.processing_status,
                verification_status:
                  event.verification_status,
                processing_error:
                  event.processing_error,
                verification_error:
                  event.verification_error,
                team_id: event.team_id,
                created_at: event.created_at
              }
            end
      }, status: :ok
    end

    private

    def subscription_readiness
      result =
        StoreSubscriptionProductionReadiness.call

      {
        ok: true,
        apple_environment:
          result[:apple_environment],
        google_credentials:
          result[:google_credentials],
        open_timeout_seconds:
          result[:open_timeout_seconds],
        read_timeout_seconds:
          result[:read_timeout_seconds]
      }
    rescue StoreSubscriptionProductionReadiness::ConfigurationError => error
      {
        ok: false,
        problems: error.problems
      }
    rescue StandardError => error
      {
        ok: false,
        problems: [
          error.message
        ]
      }
    end
  end
end
