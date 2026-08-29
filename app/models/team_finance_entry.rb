class TeamFinanceEntry < ApplicationRecord
  ENTRY_TYPES = %w[income expense].freeze

  belongs_to :team
  belongs_to :created_by,
             class_name: "User",
             optional: true
  belongs_to :match,
             optional: true

  validates :entry_type,
            presence: true,
            inclusion: {
              in: ENTRY_TYPES
            }

  validates :category,
            :description,
            :occurred_on,
            presence: true

  validates :description,
            length: {
              maximum: 180
            }

  validates :category,
            length: {
              maximum: 80
            }

  validates :amount_pence,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than: 0
            }

  scope :income,
        -> { where(entry_type: "income") }
  scope :expenses,
        -> { where(entry_type: "expense") }
end
