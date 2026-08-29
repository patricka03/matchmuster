class ConversationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :authorize_team_member!
  before_action :set_conversation,
                only: %i[show read]
  before_action :authorize_participant!,
                only: %i[show read]

  def index
    conversations =
      @team
        .conversations
        .joins(:conversation_participants)
        .where(
          conversation_participants: {
            user_id: current_user.id
          }
        )
        .includes(
          :participants,
          :conversation_participants
        )
        .order(updated_at: :desc)
        .limit(100)

    render json: {
      conversations:
        conversations.map {
          |conversation|
          conversation_json(conversation)
        }
    }, status: :ok
  end

  def show
    render json: {
      conversation: conversation_json(@conversation)
    }, status: :ok
  end

  def recipients
    blocked_ids =
      current_user.initiated_blocks.pluck(:blocked_user_id) +
      current_user.received_blocks.pluck(:blocker_id)

    users =
      User
        .joins(:team_memberships)
        .where(
          team_memberships: {
            team_id: @team.id,
            status: "approved"
          }
        )
        .where.not(id: current_user.id)
        .where.not(id: blocked_ids)
        .where(deleted_at: nil, suspended_at: nil, banned_at: nil)
        .distinct
        .order(:first_name, :last_name)

    memberships =
      @team
        .team_memberships
        .where(
          user_id: users.select(:id),
          status: "approved"
        )
        .index_by(&:user_id)

    render json: {
      recipients:
        users.map do |user|
          user_json(
            user,
            membership: memberships[user.id]
          )
        end
    }, status: :ok
  end

  def create
    recipient =
      User.find(
        conversation_params[:recipient_id]
      )

    if recipient.id == current_user.id
      return render json: {
        error: "You cannot start a conversation with yourself."
      }, status: :unprocessable_entity
    end

    unless approved_member?(recipient) && !recipient.access_restricted?
      return render json: {
        error: "You can only message approved members of this team."
      }, status: :forbidden
    end

    if Conversation.blocked_between?(
      first_user: current_user,
      second_user: recipient
    )
      return render json: {
        error: "This conversation is not available."
      }, status: :forbidden
    end

    conversation =
      Conversation.direct_between!(
        team: @team,
        first_user: current_user,
        second_user: recipient
      )

    render json: {
      conversation: conversation_json(conversation)
    }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Team member not found."
    }, status: :not_found
  end

  def read
    participant =
      @conversation.participant_record_for(current_user)

    participant&.mark_read!

    render json: {
      unread_count: 0,
      last_read_at: participant&.last_read_at
    }, status: :ok
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def authorize_team_member!
    @membership =
      current_user
        .team_memberships
        .find_by(
          team_id: @team.id,
          status: "approved"
        )

    return if @membership

    render json: {
      error: "You are not an approved member of this team."
    }, status: :forbidden
  end

  def set_conversation
    @conversation = @team.conversations.find(params[:id])
  end

  def authorize_participant!
    return if @conversation.participant?(current_user)

    render json: {
      error: "You are not part of this conversation."
    }, status: :forbidden
  end

  def approved_member?(user)
    user.team_memberships.exists?(
      team_id: @team.id,
      status: "approved"
    )
  end

  def conversation_params
    params
      .require(:conversation)
      .permit(:recipient_id)
  end

  def conversation_json(conversation)
    participant =
      conversation.participant_record_for(current_user)

    other =
      conversation.other_participant_for(current_user)

    last_message =
      conversation
        .messages
        .order(created_at: :desc)
        .first

    {
      id: conversation.id,
      team_id: conversation.team_id,
      conversation_type: conversation.conversation_type,
      other_user: user_json(other),
      last_message: message_json(last_message),
      unread_count: participant&.unread_count || 0,
      updated_at: conversation.updated_at
    }
  end

  def message_json(message)
    return nil unless message

    {
      id: message.id,
      body: message.body,
      sender_id: message.sender_id,
      created_at: message.created_at
    }
  end

  def user_json(user, membership: nil)
    return nil unless user

    membership ||=
      user.team_memberships.find_by(
        team_id: @team.id,
        status: "approved"
      )

    {
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      account_type: user.account_type,
      role: membership&.role,
      preferred_position: membership&.preferred_position
    }
  end
end
