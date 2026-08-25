class PostReadsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :set_post
  before_action :authorize_team_member!, only: %i[create]
  before_action :authorize_manager!, only: %i[index]
  before_action :ensure_post_tracks_reads!
  before_action :require_tactical_read_receipts_plus!, only: %i[ index ]

  def index
    @post_reads = @post.post_reads
                       .includes(:user)
                       .order(read_at: :desc)

    render json: @post_reads.as_json(
      only: %i[id read_at],
      include: {
        user: {
          only: %i[id first_name last_name]
        }
      }
    ), status: :ok
  end

  def create
    @post_read = @post.post_reads.find_or_initialize_by(
      user: current_user
    )

    if @post_read.persisted?
      return render json: @post_read, status: :ok
    end

    @post_read.read_at = Time.current

    if @post_read.save
      render json: @post_read, status: :created
    else
      render json: {
        errors: @post_read.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_post
    @post = @team.posts.find(params[:post_id])
  end

  def authorize_team_member!
    approved_member = current_user.team_memberships.exists?(
      team_id: @team.id,
      status: "approved"
    )

    return if approved_member

    render json: {
      error: "You are not an approved member of this team"
    }, status: :forbidden
  end

  def authorize_manager!
    verified_manager =
      current_user.account_type == "manager" &&
      current_user.manager_verification_status == "approved"

    approved_manager_membership = current_user.team_memberships.exists?(
      team_id: @team.id,
      role: "manager",
      status: "approved"
    )

    return if verified_manager && approved_manager_membership

    render json: {
      error: "Only an approved manager of this team can view post reads"
    }, status: :forbidden
  end

  def ensure_post_tracks_reads!
    return if %w[announcement tactical].include?(@post.post_type)

    render json: {
      error: "Read tracking is only available for announcements and tactical posts"
    }, status: :unprocessable_entity
  end

  def require_tactical_read_receipts_plus!
    require_plus!(
      team: @team,
      feature:
        :tactical_read_receipts
    )
  end
end
