class MatchPayment < ApplicationRecord
  PAYMENT_STATUSES = %w[pending paid waived refunded].freeze
  
  attribute :status, :string, default: "pending"

  belongs_to :user
  belongs_to :match

  validates :amount_pence, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :status, presence: true, inclusion: { in: PAYMENT_STATUSES }
  validates :user_id, uniqueness: { scope: :match_id, message: "already has a payment request for this match" }

  validate :user_must_be_approved_team_member
  validate :paid_at_matches_status

  private

  def user_must_be_approved_team_member
    return if user.blank? || match.blank?

    approved_member = user.team_memberships.exists?(team_id: match.team_id, status: "approved")

    return if approved_member
      errors.add(:user, "must be an approved member of this team")
  end

  def paid_at_matches_status
    if status == "paid" && paid_at.blank?
      errors.add(:paid_at, "must be present when payment is paid")
    elsif status != "paid" && paid_at.present?
      errors.add(:paid_at, "must be empty unless payment is paid")
    end
  end
end
