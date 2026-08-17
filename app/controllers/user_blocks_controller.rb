class UserBlocksController < ApplicationController
  before_action :authenticate_user!

  before_action :set_user_block,
                only: :destroy

  def index
    user_blocks =
      current_user
        .initiated_blocks
        .includes(
          :blocked_user
        )
        .order(
          created_at: :desc
        )

    render json: {
      user_blocks:
        user_blocks.map do |user_block|
          user_block_json(
            user_block
          )
        end
    }, status: :ok
  end

  def create
    blocked_user =
      User.find(
        user_block_params[
          :blocked_user_id
        ]
      )

    unless shares_approved_team_with?(
      blocked_user
    )
      return render json: {
        error: "You cannot block this user."
      }, status: :forbidden
    end

    user_block =
      current_user
        .initiated_blocks
        .find_or_initialize_by(
          blocked_user:
            blocked_user
        )

    new_block =
      user_block.new_record?

    if user_block.save
      render json: {
        message:
          new_block ?
            "User blocked successfully." :
            "This user is already blocked.",

        user_block:
          user_block_json(
            user_block
          )
      }, status:
        new_block ?
          :created :
          :ok
    else
      render json: {
        errors:
          user_block
            .errors
            .full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    @user_block.destroy!

    head :no_content
  end

  private

  def set_user_block
    @user_block =
      current_user
        .initiated_blocks
        .find(
          params[:id]
        )
  end

  def shares_approved_team_with?(
    user
  )
    current_team_ids =
      current_user
        .team_memberships
        .where(
          status: "approved"
        )
        .select(
          :team_id
        )

    user
      .team_memberships
      .where(
        status: "approved",
        team_id: current_team_ids
      )
      .exists?
  end

  def user_block_params
    params
      .require(:user_block)
      .permit(
        :blocked_user_id
      )
  end

  def user_block_json(user_block)
    blocked_user =
      user_block.blocked_user

    {
      id: user_block.id,
      created_at: user_block.created_at,

      blocked_user: {
        id: blocked_user.id,
        first_name: blocked_user.first_name,
        last_name: blocked_user.last_name,
        account_type: blocked_user.account_type
      }
    }
  end
end
