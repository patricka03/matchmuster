class Team < ApplicationRecord
  has_many :team_memberships, dependent: :destroy
  has_many :users, through: :team_memberships
  has_many :matches, dependent: :destroy
  has_many :posts, dependent: :destroy

  before_validation :generate_invite_code, on: :create

  validates :name, presence: true
  validates :invite_code, presence: true, uniqueness: true

  private

  def generate_invite_code
    return if invite_code.present?

    self.invite_code = loop do
      code = SecureRandom.hex(4).upcase

      break code unless Team.exists?(invite_code: code)
    end
  end
end
