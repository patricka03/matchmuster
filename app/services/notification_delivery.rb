class NotificationDelivery
  class << self
    def to_user(user:, **attributes)
      notification =
        user.notifications.create!(
          notification_attributes(attributes)
        )

      deliver_native_push(
        user: user,
        notification: notification
      )

      notification
    end

    def to_players(team:, except: nil, **attributes)
      deliver_to(
        approved_members(
          team,
          role: "player"
        ),
        except: except,
        attributes:
          attributes.merge(
            team: team
          )
      )
    end

    def to_managers(team:, except: nil, **attributes)
      managers =
        approved_members(
          team,
          role: "manager"
        )
          .where(
            account_type: "manager",
            manager_verification_status: "approved"
          )

      deliver_to(
        managers,
        except: except,
        attributes:
          attributes.merge(
            team: team
          )
      )
    end

    def to_team(team:, except: nil, **attributes)
      deliver_to(
        approved_members(team),
        except: except,
        attributes:
          attributes.merge(
            team: team
          )
      )
    end

    private

    def approved_members(team, role: nil)
      membership_conditions = {
        team_id: team.id,
        status: "approved"
      }

      membership_conditions[:role] =
        role if role.present?

      User
        .joins(:team_memberships)
        .where(
          team_memberships:
            membership_conditions
        )
        .distinct
    end

    def deliver_to(scope, except:, attributes:)
      excluded_ids =
        Array(except)
          .compact
          .map do |user_or_id|
            if user_or_id.respond_to?(:id)
              user_or_id.id
            else
              user_or_id
            end
          end

      recipients =
        if excluded_ids.any?
          scope.where.not(
            id: excluded_ids
          )
        else
          scope
        end

      notification_data =
        notification_attributes(
          attributes
        )

      deliveries = []

      Notification.transaction do
        recipients.find_each do |recipient|
          notification =
            recipient.notifications.create!(
              notification_data
            )

          deliveries << [
            recipient,
            notification
          ]
        end
      end

      deliveries.each do |recipient, notification|
        deliver_native_push(
          user: recipient,
          notification: notification
        )
      end

      deliveries.length
    end

    def deliver_native_push(user:, notification:)
      FirebasePushService.to_user(
        user: user,
        title: notification.title,
        body: notification.message,
        data: push_data(notification)
      )
    rescue StandardError => error
      Rails.logger.error(
        "Native push delivery failed for " \
        "Notification #{notification.id}: " \
        "#{error.class}: #{error.message}"
      )

      0
    end

    def push_data(notification)
      {
        notification_id:
          notification.id,

        notification_type:
          notification.notification_type,

        team_id:
          notification.team_id,

        match_id:
          notification.match_id,

        post_id:
          notification.post_id,

        match_payment_id:
          notification.match_payment_id,

        featured_user_id:
          notification.featured_user_id
      }
    end

    def notification_attributes(attributes)
      attributes.slice(
        :title,
        :message,
        :notification_type,
        :actor,
        :featured_user,
        :team,
        :match,
        :post,
        :match_payment
      )
    end
  end
end
