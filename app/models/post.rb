class Post < ApplicationRecord
  belongs_to :team
  belongs_to :user

  has_many :post_reads, dependent: :destroy
  has_many :readers, through: :post_reads, source: :user
  has_many :reports, as: :reportable, dependent: :nullify


  POST_TYPES = %w[announcement tactical general].freeze

  validates :title, :content, :post_type, presence: true
  validates :post_type, inclusion: { in: POST_TYPES }
  validate :author_must_be_approved_team_member
  validate :only_managers_can_create_manager_posts
  validates :title, :content, objectionable_content: true

  private

  def author_must_be_approved_team_member
    return if user.blank? || team.blank?

    approved_member = user.team_memberships.exists?(team_id: team_id, status: "approved")

    unless approved_member
      errors.add(:user, "must be an approved member of this team")
    end
  end

  def only_managers_can_create_manager_posts
    return unless %w[announcement tactical].include?(post_type)
    return if user.blank? || team.blank?

    approved_manager = user.team_memberships.exists?(team_id: team_id, role: "manager", status: "approved")

    unless approved_manager
      errors.add(:post_type, "can only be used by an approved team manager")
    end
  end
end
