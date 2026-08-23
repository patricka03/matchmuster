class Team < ApplicationRecord
  has_many :team_memberships, dependent: :destroy

  has_many :users,
           through: :team_memberships

  has_many :matches, dependent: :destroy

  has_many :posts, dependent: :destroy

  has_many :trainings, dependent: :destroy

  has_one :team_entitlement,
          dependent: :destroy

  has_one_attached :badge

  before_validation :generate_invite_code,
                    on: :create

  validates :name,
            presence: true

  validates :invite_code,
            presence: true,
            uniqueness: true

  # ========================================
  # SUBSCRIPTION / ENTITLEMENT
  # ========================================

  def plus?(at: Time.current)
    team_entitlement&.plus_active?(
      at: at
    ) || false
  end

  def free?(at: Time.current)
    !plus?(at: at)
  end

  def effective_plan(at: Time.current)
    plus?(at: at) ? "plus" : "free"
  end

  def plus_days_remaining(at: Time.current)
    team_entitlement&.days_remaining(
      at: at
    )
  end

  def plus_source
    team_entitlement&.source
  end

  def founder_plus?
    team_entitlement&.founder? || false
  end

  private

  def generate_invite_code
    return if invite_code.present?

    self.invite_code = loop do
      code =
        SecureRandom.hex(4).upcase

      break code unless Team.exists?(
        invite_code: code
      )
    end
  end
end
