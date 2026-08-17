class Developer < ApplicationRecord
  include Devise::JWT::RevocationStrategies::JTIMatcher

  has_many :reviewed_reports, class_name: "Report", foreign_key: :reviewed_by_id, inverse_of: :reviewed_by, dependent: :nullify
  has_many :moderation_actions, dependent: :nullify
  devise :database_authenticatable, :recoverable, :rememberable, :validatable, :jwt_authenticatable, jwt_revocation_strategy: self

  self.skip_session_storage = [ :http_auth, :params_auth, :jwt ]
end
