class Team < ApplicationRecord
  BILLING_ACCOUNT_TOKEN_FORMAT =
    /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i.freeze

  belongs_to :owner_user,
             class_name: "User",
             optional: true,
             inverse_of: :owned_teams

  has_many :team_memberships,
           dependent: :destroy

  has_many :users,
           through: :team_memberships

  has_many :matches,
           dependent: :destroy

  has_many :posts,
           dependent: :destroy

  has_many :trainings,
           dependent: :destroy

  has_many :conversations,
           dependent: :destroy

  has_many :team_finance_entries,
           dependent: :destroy

  has_many :match_payments,
           dependent: :destroy

  has_many :payment_templates,
           dependent: :destroy

  has_many :disciplinary_records,
           dependent: :destroy

  has_many :player_fitness_statuses,
           dependent: :destroy

  has_many :availability_status_changes,
           dependent: :destroy

  has_one :team_entitlement,
          dependent: :destroy

  has_one_attached :badge

  before_validation :generate_invite_code,
                    on: :create

  before_validation :generate_billing_account_token,
                    on: :create

  validates :name,
            presence: true

  validates :invite_code,
            presence: true,
            uniqueness: true

  validates :billing_account_token,
            presence: true,
            uniqueness: true,
            format: {
              with: BILLING_ACCOUNT_TOKEN_FORMAT
            }

  def plus?(at: Time.current)
    team_entitlement&.plus_active?(
      at: at
    ) || false
  end

  def plus_active?(at: Time.current)
    plus?(
      at: at
    )
  end

  def free?(at: Time.current)
    !plus?(
      at: at
    )
  end

  def effective_plan(at: Time.current)
    plus?(
      at: at
    ) ? "plus" : "free"
  end

  def subscription_status
    team_entitlement&.status || "free"
  end

  def subscription_ends_at
    team_entitlement&.ends_at
  end

  def subscription_days_remaining(at: Time.current)
    team_entitlement&.days_remaining(
      at: at
    )
  end

  def launch_club?
    launch_club_since.present?
  end

  def canonical_owner
    owner_user ||
      team_memberships
        .includes(:user)
        .where(
          role: "manager",
          status: "approved"
        )
        .order(
          :created_at,
          :id
        )
        .first
        &.user
  end

  def owned_by?(user)
    return false unless user

    canonical_owner&.id == user.id
  end

  private

  def generate_invite_code
    return if invite_code.present?

    self.invite_code =
      loop do
        code = SecureRandom.hex(4).upcase

        break code unless
          Team.exists?(
            invite_code: code
          )
      end
  end

  def generate_billing_account_token
    return if billing_account_token.present?

    self.billing_account_token =
      loop do
        token = SecureRandom.uuid

        break token unless
          Team.exists?(
            billing_account_token: token
          )
      end
  end
end
