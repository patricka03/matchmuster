class SocialIdentity < ApplicationRecord
  PROVIDERS = %w[apple google].freeze

  belongs_to :user

  validates :provider,
            presence: true,
            inclusion: {
              in: PROVIDERS
            }

  validates :uid,
            presence: true,
            uniqueness: {
              scope: :provider
            }

  validates :provider,
            uniqueness: {
              scope: :user_id
            }
end
