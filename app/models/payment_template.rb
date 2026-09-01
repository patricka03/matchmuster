class PaymentTemplate < ApplicationRecord
  RECURRENCES = %w[none monthly].freeze

  belongs_to :team
  belongs_to :created_by,
             class_name: "User",
             optional: true

  validates :name, :title, :payment_type, :amount_pence,
            :default_due_days, :recurrence,
            presence: true
  validates :name, uniqueness: { scope: :team_id }
  validates :payment_type,
            inclusion: { in: MatchPayment::PAYMENT_TYPES }
  validates :payment_type,
            exclusion: {
              in: MatchPayment::FINE_TYPES,
              message: "cannot be used for recurring player fines"
            }
  validates :recurrence, inclusion: { in: RECURRENCES }
  validates :amount_pence,
            numericality: { only_integer: true, greater_than: 0 }
  validates :default_due_days,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 365
            }
  validates :title, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }, allow_blank: true
  validate :monthly_template_needs_next_run_date
  validate :monthly_template_cannot_be_match_sub

  scope :active_recurring,
        -> { where(active: true, recurrence: "monthly") }

  private

  def monthly_template_needs_next_run_date
    return unless recurrence == "monthly" && next_run_on.blank?

    errors.add(:next_run_on, "must be present for a monthly payment")
  end

  def monthly_template_cannot_be_match_sub
    return unless recurrence == "monthly" && payment_type == "match_sub"

    errors.add(:payment_type, "cannot repeat monthly because Match Subs need a fixture")
  end
end
