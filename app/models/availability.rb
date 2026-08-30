class Availability < ApplicationRecord
  STATUS = %w[
    available
    unavailable
  ].freeze

  attr_reader :removed_from_matchday_squad

  before_validation :normalise_status

  after_save :remove_from_matchday_squad_if_unavailable,
             if: :became_unavailable_before_kickoff?

  after_update :record_status_change,
               if: :saved_change_to_status?

  belongs_to :user
  belongs_to :match

  validates :status,
            presence: true,
            inclusion: {
              in: STATUS
            }

  validates :user_id,
            uniqueness: {
              scope: :match_id
            }

  def removed_from_matchday_squad?
    removed_from_matchday_squad == true
  end

  private

  def normalise_status
    self.status =
      status
        .to_s
        .downcase
        .strip
  end

  def became_unavailable_before_kickoff?
    return false unless saved_change_to_status?
    return false unless status == "unavailable"
    return false if match.blank?
    return false if match.kickoff_time.blank?

    Time.current < match.kickoff_time
  end

  def remove_from_matchday_squad_if_unavailable
    squad_selection =
      match
        .squad_selections
        .find_by(
          user_id: user_id
        )

    return unless squad_selection

    squad_selection.destroy!

    @removed_from_matchday_squad =
      true
  end

  def record_status_change
    AvailabilityStatusChange.create!(
      team: match.team,
      match: match,
      user: user,
      from_status: status_before_last_save,
      to_status: status,
      was_selected: match.squad_selections.exists?(user_id: user_id),
      changed_at: Time.current
    )
  end
end
