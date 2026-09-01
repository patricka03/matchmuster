class MatchPayment < ApplicationRecord
  PAYMENT_TYPES = %w[
    match_sub training_sub yellow_card_fine second_yellow_fine red_card_fine
    disciplinary_fine membership_fee kit_payment tournament_fee
    transport_contribution social_event other
  ].freeze

  FINE_TYPES = %w[
    yellow_card_fine second_yellow_fine red_card_fine disciplinary_fine
  ].freeze

  PAYMENT_STATUSES = %w[
    pending cash_pending partially_paid paid waived cancelled refunded
  ].freeze

  PAYMENT_METHODS = %w[stripe cash bank_transfer other].freeze

  TYPE_LABELS = {
    "match_sub" => "Match Subs",
    "training_sub" => "Training Subs",
    "yellow_card_fine" => "Yellow-card fine",
    "second_yellow_fine" => "Second-yellow fine",
    "red_card_fine" => "Red-card fine",
    "disciplinary_fine" => "Disciplinary fine",
    "membership_fee" => "Membership fee",
    "kit_payment" => "Kit payment",
    "tournament_fee" => "Tournament fee",
    "transport_contribution" => "Transport contribution",
    "social_event" => "Social event",
    "other" => "Team payment"
  }.freeze

  attribute :status, :string, default: "pending"
  attribute :payment_type, :string, default: "match_sub"
  attribute :amount_paid_pence, :integer, default: 0
  attribute :refunded_amount_pence, :integer, default: 0

  belongs_to :user
  belongs_to :team
  belongs_to :match, optional: true
  belongs_to :requested_by, class_name: "User", optional: true

  has_one :disciplinary_record, dependent: :nullify
  has_many :notifications, dependent: :nullify

  before_validation :copy_team_from_match
  before_validation :apply_default_title
  before_validation :normalise_legacy_status_fields

  validates :amount_pence,
            presence: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :amount_paid_pence,
            :refunded_amount_pence,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }
  validates :status, presence: true, inclusion: { in: PAYMENT_STATUSES }
  validates :payment_type, presence: true, inclusion: { in: PAYMENT_TYPES }
  validates :payment_method,
            inclusion: { in: PAYMENT_METHODS },
            allow_nil: true
  validates :title, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }, allow_blank: true
  validates :batch_key, uniqueness: true, allow_nil: true

  validate :user_must_be_approved_team_member
  validate :match_must_belong_to_team
  validate :match_required_for_match_sub_or_fine
  validate :payment_amounts_are_consistent
  validate :status_metadata_is_consistent
  validate :one_match_sub_per_player_and_match

  scope :outstanding,
        -> { where(status: %w[pending cash_pending partially_paid]) }
  scope :fines, -> { where(payment_type: FINE_TYPES) }
  scope :match_subs, -> { where(payment_type: "match_sub") }

  def type_label
    TYPE_LABELS.fetch(payment_type, "Team payment")
  end

  def outstanding?
    %w[pending cash_pending partially_paid].include?(status)
  end

  def fine?
    FINE_TYPES.include?(payment_type)
  end

  def amount_outstanding_pence
    [amount_pence - amount_paid_pence, 0].max
  end

  def overdue?(at: Time.current)
    outstanding? && due_at.present? && due_at < at
  end

  def record_payment!(amount_pence:, method:, paid_at: Time.current)
    amount = Integer(amount_pence)

    raise ArgumentError, "Payment amount must be greater than zero" unless amount.positive?
    raise ArgumentError, "Payment exceeds the outstanding balance" if amount > amount_outstanding_pence
    raise ArgumentError, "Unsupported payment method" unless PAYMENT_METHODS.include?(method)

    new_total = self.amount_paid_pence + amount

    update!(
      amount_paid_pence: new_total,
      payment_method: method,
      status: new_total == self.amount_pence ? "paid" : "partially_paid",
      paid_at: new_total == self.amount_pence ? paid_at : nil,
      cash_confirmation_requested_at: nil
    )
  end

  private

  def copy_team_from_match
    self.team ||= match&.team
  end

  def apply_default_title
    self.title = type_label if title.blank?
  end

  def user_must_be_approved_team_member
    return if user.blank? || team.blank?
    return if user.team_memberships.exists?(
      team_id: team_id,
      role: "player",
      status: "approved"
    )

    errors.add(:user, "must be an approved player for this team")
  end

  def match_must_belong_to_team
    return if match.blank? || team.blank? || match.team_id == team_id

    errors.add(:match, "must belong to this team")
  end

  def match_required_for_match_sub_or_fine
    return unless payment_type == "match_sub" || fine?
    return if match.present?

    errors.add(:match, "must be selected for Match Subs and player fines")
  end

  def payment_amounts_are_consistent
    if amount_paid_pence.to_i > amount_pence.to_i
      errors.add(:amount_paid_pence, "cannot exceed the requested amount")
    end

    if refunded_amount_pence.to_i > amount_paid_pence.to_i
      errors.add(:refunded_amount_pence, "cannot exceed the amount paid")
    end
  end

  def status_metadata_is_consistent
    if status == "paid"
      errors.add(:paid_at, "must be present when payment is paid") if paid_at.blank?
      if amount_paid_pence.to_i != amount_pence.to_i
        errors.add(:amount_paid_pence, "must equal the requested amount when paid")
      end
    elsif status != "refunded" && paid_at.present?
      errors.add(:paid_at, "must be empty unless payment is paid")
    end

    if status == "waived" && waived_at.blank?
      errors.add(:waived_at, "must be present when payment is waived")
    end

    if status == "cancelled" && cancelled_at.blank?
      errors.add(:cancelled_at, "must be present when payment is cancelled")
    end

    if status == "refunded"
      errors.add(:refunded_at, "must be present when payment is refunded") if refunded_at.blank?
      if refunded_amount_pence.to_i != amount_paid_pence.to_i
        errors.add(:refunded_amount_pence, "must equal the paid amount when fully refunded")
      end
    end
  end

  def normalise_legacy_status_fields
    if status == "paid" && amount_pence.present?
      self.amount_paid_pence = amount_pence if amount_paid_pence.to_i.zero?
      self.payment_method ||=
        stripe_payment_intent_id.present? ? "stripe" : "cash"
    elsif status == "waived"
      self.waived_at ||= Time.current
    elsif status == "refunded" && amount_pence.present?
      self.amount_paid_pence = amount_pence if amount_paid_pence.to_i.zero?
      self.refunded_amount_pence = amount_paid_pence if refunded_amount_pence.to_i.zero?
      self.refunded_at ||= Time.current
    end
  end

  def one_match_sub_per_player_and_match
    return unless payment_type == "match_sub" && match_id.present? && user_id.present?

    duplicate = self.class.where(
      match_id: match_id,
      user_id: user_id,
      payment_type: "match_sub"
    )
    duplicate = duplicate.where.not(id: id) if persisted?

    errors.add(:user, "already has a Match Subs request for this match") if duplicate.exists?
  end
end
