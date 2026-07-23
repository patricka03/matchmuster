class Team < ApplicationRecord
  has_many :team_memberships, dependent: :destroy
  has_many :users, through: :team_memberships

  validates :name, :invite_code, presence: true
  validates :invite_code, uniqueness: true
end
