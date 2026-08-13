class LegalAcceptance < ApplicationRecord
  belongs_to :user

  DOCUMENT_TYPES = %w[
    terms
    age_declaration
    privacy_notice
  ].freeze

  validates :document_type,
            presence: true,
            inclusion: { in: DOCUMENT_TYPES }

  validates :document_version, presence: true
  validates :accepted_at, presence: true

  validates :document_type,
            uniqueness: {
              scope: [:user_id, :document_version]
            }
end
