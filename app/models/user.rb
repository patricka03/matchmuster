class User < ApplicationRecord
before_validation :set_manager_verification_status, on: :create

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable

  include Devise::JWT::RevocationStrategies::JTIMatcher
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :jwt_authenticatable, jwt_revocation_strategy: self

  self.skip_session_storage = [:http_auth, :params_auth]

  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships

  validates :first_name, :last_name, :account_type, presence: true
  validates :account_type, inclusion: { in: %w[player manager] }

  validates :manager_verification_status, presence: true, inclusion: { in: %w[pending approved rejected]},  if: :manager?

  def manager?
    account_type == "manager"
  end

  private

  def set_manager_verification_status
    self.manager_verification_status = "pending" if manager?
  end

end
