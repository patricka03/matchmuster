class PostRead < ApplicationRecord
  belongs_to :post
  belongs_to :user

  validates :read_at, presence: true

  validates :user_id, uniqueness: { scope: :post_id, message: "has already been recorded as having read this post" }

  validate :user_must_be_approved_team_member
  validate :post_must_require_read_tracking

  private

  def user_must_be_approved_team_member
    return if user.blank? || post.blank?

    approved_member = user.team_memberships.exists?(team_id: post.team_id, status: "approved")

    unless approved_member
      errors.add(:user, "must be an approved member of this team")
    end
  end

  def post_must_require_read_tracking
    return if post.blank?
    return if %w[announcement tactical].include?(post.post_type)

    errors.add(:post, "must be an announcement or tactical post")
  end
end
