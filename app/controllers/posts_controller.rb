class PostsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :authorize_team_member!
  before_action :set_post,
                only: %i[
                  show
                  update
                  destroy
                ]

  before_action :authorize_post_management!,
                only: %i[
                  update
                  destroy
                ]

  # ========================================
  # INDEX
  # ========================================

  def index
    @posts =
      @team
        .posts
        .includes(:user)
        .order(
          pinned: :desc,
          created_at: :desc
        )

    render json:
      @posts.as_json(
        include: {
          user: {
            only: %i[
              id
              first_name
            ]
          }
        }
      )
  end

  # ========================================
  # SHOW
  # ========================================

  def show
    record_post_read

    render json:
      @post.as_json(
        include: {
          user: {
            only: %i[
              id
              first_name
            ]
          }
        }
      ),
      status: :ok
  end

  # ========================================
  # CREATE
  # ========================================

  def create
    @post =
      @team.posts.new(
        post_params
      )

    @post.user =
      current_user

    if @post.save
      create_post_notifications

      render json: @post,
             status: :created
    else
      render json: {
        errors:
          @post
            .errors
            .full_messages
      }, status: :unprocessable_entity
    end
  end

  # ========================================
  # UPDATE
  # ========================================

  def update
    if @post.update(
      post_params
    )
      if important_post_details_changed?
        create_post_notifications(
          updated: true
        )
      end

      render json: @post,
             status: :ok
    else
      render json: {
        errors:
          @post
            .errors
            .full_messages
      }, status: :unprocessable_entity
    end
  end

  # ========================================
  # DESTROY
  # ========================================

  def destroy
    @post.destroy!

    head :no_content
  end

  private

  # ========================================
  # SET TEAM / POST
  # ========================================

  def set_team
    @team =
      Team.find(
        params[:team_id]
      )
  end

  def set_post
    @post =
      @team
        .posts
        .find(
          params[:id]
        )
  end

  # ========================================
  # AUTHORISATION
  # ========================================

  def authorize_team_member!
    approved_member =
      current_user
        .team_memberships
        .exists?(
          team_id: @team.id,
          status: "approved"
        )

    return if approved_member

    render json: {
      error:
        "You are not an approved member of this team"
    }, status: :forbidden
  end

  def authorize_post_management!
    return if
      @post.user_id ==
      current_user.id

    return if
      approved_manager?

    render json: {
      error:
        "You are not authorised to manage this post"
    }, status: :forbidden
  end

  def approved_manager?
    current_user
      .team_memberships
      .exists?(
        team_id: @team.id,
        role: "manager",
        status: "approved"
      )
  end

  # ========================================
  # STRONG PARAMS
  # ========================================

  def post_params
    permitted =
      params
        .require(:post)
        .permit(
          :title,
          :content,
          :post_type,
          :pinned
        )

    permitted.delete(
      :pinned
    ) unless approved_manager?

    permitted
  end

  # ========================================
  # POST READS
  # ========================================

  def record_post_read
    return unless
      %w[
        announcement
        tactical
      ].include?(
        @post.post_type
      )

    return if
      @post.user_id ==
      current_user.id

    @post
      .post_reads
      .find_or_create_by!(
        user: current_user
      ) do |post_read|
        post_read.read_at =
          Time.current
      end
  end

  # ========================================
  # BACKGROUND POST NOTIFICATIONS
  # ========================================

  def create_post_notifications(updated: false)
    return if
      @post.post_type ==
      "general"

    PostNotificationJob.perform_later(
      team_id: @team.id,
      post_id: @post.id,
      updated: updated
    )
  end

  def important_post_details_changed?
    important_fields = %w[
      title
      content
      post_type
    ]

    (
      @post.saved_changes.keys &
      important_fields
    ).any?
  end
end
