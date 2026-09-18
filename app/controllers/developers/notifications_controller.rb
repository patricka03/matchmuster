module Developers
  class NotificationsController < BaseController
    VALID_SCOPES = %w[
      all
      managers
      players
      team
      user
    ].freeze

    def create
      title =
        notification_params[
          :title
        ]
          .to_s
          .strip

      message =
        notification_params[
          :message
        ]
          .to_s
          .strip

      scope =
        notification_params[
          :scope
        ]
          .to_s

      notes =
        notification_params[
          :notes
        ]
          .to_s
          .strip

      if title.blank? ||
         message.blank?
        return render json: {
          error:
            "Title and message are required."
        }, status: :unprocessable_entity
      end

      unless VALID_SCOPES.include?(
        scope
      )
        return render json: {
          error:
            "Invalid notification audience."
        }, status: :unprocessable_entity
      end

      if notes.blank?
        return render json: {
          error:
            "A developer audit note is required."
        }, status: :unprocessable_entity
      end

      recipients =
        recipients_for(
          scope
        )

      recipient_count = 0

      Notification.transaction do
        recipients.find_each do |user|
          Notification.create!(
            user: user,
            team_id:
              scope == "team" ?
                notification_params[
                  :team_id
                ] :
                nil,
            title: title,
            message: message,
            notification_type:
              "app_update"
          )

          recipient_count += 1
        end
      end

      DeveloperPlatformAudit.record!(
        developer:
          current_developer,
        action_type:
          "notification_sent",
        notes:
          notes,
        metadata: {
          scope: scope,
          team_id:
            notification_params[
              :team_id
            ],
          user_id:
            notification_params[
              :user_id
            ],
          title:
            title,
          recipient_count:
            recipient_count
        }
      )

      render json: {
        message:
          "Notification sent.",
        recipient_count:
          recipient_count
      }, status: :created
    end

    private

    def notification_params
      params
        .require(
          :notification
        )
        .permit(
          :title,
          :message,
          :scope,
          :team_id,
          :user_id,
          :notes
        )
    end

    def active_users
      User.where(
        deleted_at: nil,
        suspended_at: nil,
        banned_at: nil
      )
    end

    def recipients_for(scope)
      case scope
      when "all"
        active_users

      when "managers"
        active_users.where(
          account_type:
            "manager",
          manager_verification_status:
            "approved"
        )

      when "players"
        active_users.where(
          account_type:
            "player"
        )

      when "team"
        team_id =
          notification_params[
            :team_id
          ]

        raise ActiveRecord::RecordNotFound,
              "Team not found" if
          team_id.blank?

        team =
          Team.find(
            team_id
          )

        active_users.where(
          id:
            team
              .team_memberships
              .where(
                status:
                  "approved"
              )
              .select(
                :user_id
              )
        )

      when "user"
        user_id =
          notification_params[
            :user_id
          ]

        raise ActiveRecord::RecordNotFound,
              "User not found" if
          user_id.blank?

        active_users.where(
          id:
            user_id
        )
      end
    end
  end
end
