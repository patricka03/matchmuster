class User < ApplicationRecord
  before_validation :set_manager_verification_status, on: :create

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable

  include Devise::JWT::RevocationStrategies::JTIMatcher
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :jwt_authenticatable, jwt_revocation_strategy: self

  self.skip_session_storage = [:http_auth, :params_auth, :jwt]

  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships
  has_many :squad_selections, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :match_payments, dependent: :destroy


  has_many :availabilities, dependent: :destroy
  has_many :matches, through: :availabilities
  has_many :post_reads, dependent: :destroy

  has_many :read_posts, through: :post_reads, source: :post

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
