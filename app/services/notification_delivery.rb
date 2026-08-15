class NotificationDelivery
  class << self
    def to_user(user:, **attributes)
      user.notifications.create!(
        notification_attributes(attributes)
      )
    end

    def to_players(team:, except: nil, **attributes)
      deliver_to(
        approved_members(team, role: "player"),
        except: except,
        attributes: attributes.merge(team: team)
      )
    end

    def to_managers(team:, except: nil, **attributes)
      managers =
        approved_members(team, role: "manager")
          .where(
            account_type: "manager",
            manager_verification_status: "approved"
          )

      deliver_to(
        managers,
        except: except,
        attributes: attributes.merge(team: team)
      )
    end

    def to_team(team:, except: nil, **attributes)
      deliver_to(
        approved_members(team),
        except: except,
        attributes: attributes.merge(team: team)
      )
    end

    private

    def approved_members(team, role: nil)
      membership_conditions = {
        team_id: team.id,
        status: "approved"
      }

      membership_conditions[:role] = role if role.present?

      User
        .joins(:team_memberships)
        .where(team_memberships: membership_conditions)
        .distinct
    end

    def deliver_to(scope, except:, attributes:)
      excluded_ids =
        Array(except).compact.map do |user_or_id|
          user_or_id.respond_to?(:id) ? user_or_id.id : user_or_id
        end

      recipients =
        if excluded_ids.any?
          scope.where.not(id: excluded_ids)
        else
          scope
        end

      notification_data =
        notification_attributes(attributes)

      Notification.transaction do
        recipients.find_each do |recipient|
          recipient.notifications.create!(
            notification_data
          )
        end
      end

      recipients.count
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
