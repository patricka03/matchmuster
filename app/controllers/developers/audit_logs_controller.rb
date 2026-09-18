module Developers
  class AuditLogsController < BaseController
    def index
      limit =
        params
          .fetch(
            :limit,
            200
          )
          .to_i
          .clamp(
            1,
            500
          )

      platform_actions =
        DeveloperPlatformAction
          .includes(:developer)
          .order(
            created_at: :desc
          )
          .limit(
            limit
          )
          .map do |action|
            {
              id:
                "platform-#{action.id}",
              source:
                "platform",
              action_type:
                action.action_type,
              notes:
                action.notes,
              metadata:
                action.metadata,
              target_type:
                action.target_type,
              target_id:
                action.target_id,
              developer_email:
                action.developer.email,
              created_at:
                action.created_at
            }
          end

      account_actions =
        DeveloperAccountAction
          .includes(
            :developer,
            :target_user
          )
          .order(
            created_at: :desc
          )
          .limit(
            limit
          )
          .map do |action|
            {
              id:
                "account-#{action.id}",
              source:
                "account",
              action_type:
                action.action_type,
              notes:
                action.notes,
              metadata:
                action.metadata,
              target_type:
                "User",
              target_id:
                action.target_user_id,
              developer_email:
                action.developer.email,
              created_at:
                action.created_at
            }
          end

      moderation_actions =
        ModerationAction
          .includes(:developer)
          .order(
            created_at: :desc
          )
          .limit(
            limit
          )
          .map do |action|
            {
              id:
                "moderation-#{action.id}",
              source:
                "moderation",
              action_type:
                action.action_type,
              notes:
                action.notes,
              metadata:
                action.metadata,
              target_type:
                "User",
              target_id:
                action.target_user_id,
              developer_email:
                action.developer&.email,
              created_at:
                action.created_at
            }
          end

      actions =
        (
          platform_actions +
          account_actions +
          moderation_actions
        )
          .sort_by do |action|
            action[
              :created_at
            ]
          end
          .reverse
          .first(
            limit
          )

      render json: {
        actions: actions
      }, status: :ok
    end
  end
end
