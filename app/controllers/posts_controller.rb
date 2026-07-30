class PostsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :authorize_team_member!
  before_action :set_post, only: %i[update destroy]
  before_action :authorize_post_management!, only: %i[update destroy]

  def index
    @posts = @team.posts
                  .includes(:user)
                  .order(pinned: :desc, created_at: :desc)

    render json: @posts.as_json(
      include: {
        user: {
          only: %i[id name]
        }
      }
    )
  end

  def create
    @post = @team.posts.new(post_params)
    @post.user = current_user

    if @post.save
      render json: @post, status: :created
    else
      render json: {
        errors: @post.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def update
    if @post.update(post_params)
      render json: @post, status: :ok
    else
      render json: {
        errors: @post.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy

    head :no_content
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_post
    @post = @team.posts.find(params[:id])
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

  def authorize_post_management!
    return if @post.user_id == current_user.id
    return if approved_manager?

    render json: {
      error: "You are not authorised to manage this post"
    }, status: :forbidden
  end

  def approved_manager?
    current_user.team_memberships.exists?(
      team_id: @team.id,
      role: "manager",
      status: "approved"
    )
  end

  def post_params
    permitted = params.require(:post).permit(
      :title,
      :content,
      :post_type,
      :pinned
    )

    permitted.delete(:pinned) unless approved_manager?

    permitted
  end
end
