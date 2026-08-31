class NotificationDelivery
  class << self
    def to_user(user:, **attributes)
      notification =
        user.notifications.create!(
          notification_attributes(attributes)
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

def to_user_once(
  user:,
  deduplication_key:,
  **attributes
)
  existing =
    user
      .notifications
      .find_by(
        deduplication_key:
          deduplication_key
      )

  return existing if existing

  notification =
    user.notifications.create!(
      notification_attributes(
        attributes
      ).merge(
        deduplication_key:
          deduplication_key
      )
    )

  notification
rescue ActiveRecord::RecordNotUnique
  user
    .notifications
    .find_by!(
      deduplication_key:
        deduplication_key
    )
end

def to_users_once(
  users:,
  deduplication_key:,
  **attributes
)
  Array(users).each do |user|
    to_user_once(
      user: user,
      deduplication_key:
        deduplication_key,
      **attributes
    )
  end
end

def to_managers_once(
  team:,
  deduplication_key:,
  except: nil,
  **attributes
)
  excluded_ids =
    Array(except)
      .compact
      .map do |user_or_id|
        user_or_id.respond_to?(:id) ?
          user_or_id.id :
          user_or_id
      end

  managers =
    approved_members(
      team,
      role: "manager"
    )
      .where(
        account_type:
          "manager",
        manager_verification_status:
          "approved"
      )

  if excluded_ids.any?
    managers =
      managers.where.not(
        id: excluded_ids
      )
  end

  managers.find_each do |manager|
    to_user_once(
      user: manager,
      deduplication_key:
        deduplication_key,
      team: team,
      **attributes
    )
  end
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

      deliveries.length
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
        :training,
        :conversation,
        :post,
        :match_payment
      )
    end
  end
end
