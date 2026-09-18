module Developers
  class SubscriptionsController < BaseController
    def index
      entitlements =
        TeamEntitlement
          .includes(
            team:
              :owner_user
          )
          .order(
            updated_at: :desc
          )

      if params[:provider].present?
        entitlements =
          entitlements.where(
            provider:
              params[:provider]
          )
      end

      if params[:status].present?
        entitlements =
          entitlements.where(
            status:
              params[:status]
          )
      end

      if params[:source].present?
        entitlements =
          entitlements.where(
            source:
              params[:source]
          )
      end

      events =
        StoreSubscriptionEvent
          .includes(:team)
          .order(
            created_at: :desc
          )
          .limit(100)

      render json: {
        entitlements:
          entitlements
            .limit(200)
            .map do |entitlement|
              entitlement_json(
                entitlement
              )
            end,
        events:
          events.map do |event|
            event_json(
              event
            )
          end,
        summary:
          subscription_summary
      }, status: :ok
    end

    private

    def entitlement_json(
      entitlement
    )
      team =
        entitlement.team

      {
        id: entitlement.id,
        team: {
          id: team.id,
          name: team.name
        },
        owner:
          team.canonical_owner && {
            id:
              team.canonical_owner.id,
            email:
              team.canonical_owner.email
          },
        plan:
          entitlement.effective_plan,
        raw_plan:
          entitlement.plan,
        status:
          entitlement.status,
        source:
          entitlement.source,
        plus_active:
          entitlement.plus_active?,
        provider:
          entitlement.provider,
        billing_period:
          entitlement.billing_period,
        provider_product_id:
          entitlement.provider_product_id,
        provider_base_plan_id:
          entitlement.provider_base_plan_id,
        provider_subscription_id:
          entitlement.provider_subscription_id,
        auto_renews:
          entitlement.auto_renews,
        starts_at:
          entitlement.starts_at,
        ends_at:
          entitlement.ends_at,
        days_remaining:
          entitlement.days_remaining,
        last_store_event_at:
          entitlement.last_store_event_at,
        updated_at:
          entitlement.updated_at
      }
    end

    def event_json(event)
      {
        id: event.id,
        provider:
          event.provider,
        provider_event_id:
          event.provider_event_id,
        event_type:
          event.event_type,
        environment:
          event.environment,
        processing_status:
          event.processing_status,
        verification_status:
          event.verification_status,
        processing_error:
          event.processing_error,
        verification_error:
          event.verification_error,
        team:
          event.team && {
            id:
              event.team.id,
            name:
              event.team.name
          },
        occurred_at:
          event.occurred_at,
        created_at:
          event.created_at
      }
    end

    def subscription_summary
      entitlements =
        TeamEntitlement
          .all
          .to_a

      {
        active_plus:
          entitlements.count(
            &:plus_active?
          ),
        apple:
          entitlements.count do |entitlement|
            entitlement.plus_active? &&
              entitlement.provider ==
                "apple"
          end,
        google_play:
          entitlements.count do |entitlement|
            entitlement.plus_active? &&
              entitlement.provider ==
                "google_play"
          end,
        founder:
          entitlements.count do |entitlement|
            entitlement.plus_active? &&
              entitlement.source ==
                "founder"
          end,
        admin:
          entitlements.count do |entitlement|
            entitlement.plus_active? &&
              entitlement.source ==
                "admin"
          end,
        trialing:
          entitlements.count do |entitlement|
            entitlement.plus_active? &&
              entitlement.status ==
                "trialing"
          end,
        failed_events:
          StoreSubscriptionEvent.where(
            "processing_status = ? OR verification_status IN (?)",
            "failed",
            %w[
              failed
              rejected
            ]
          ).count
      }
    end
  end
end
