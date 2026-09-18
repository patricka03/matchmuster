class DeveloperPlatformAction < ApplicationRecord
  ACTION_TYPES = %w[
    team_created
    team_updated
    team_deleted
    team_invite_regenerated
    team_owner_transferred
    membership_added
    membership_updated
    membership_removed
    plus_granted
    plus_extended
    plus_revoked
    founder_granted
    founder_revoked
    subscription_reconcile_requested
    notification_sent
    password_reset_sent
    manager_approved
    manager_rejected
    launch_club_granted
    app_update_sent
  ].freeze

  belongs_to :developer

  validates :action_type,
            presence: true,
            inclusion: {
              in: ACTION_TYPES
            }

  validates :notes,
            presence: true,
            length: {
              maximum: 2_000
            }

  validates :target_type,
            length: {
              maximum: 80
            },
            allow_nil: true

  def target_label
    return nil if target_type.blank?

    "#{target_type} ##{target_id}"
  end
end
