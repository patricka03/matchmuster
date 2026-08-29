class MessagesController < ApplicationController
  MAX_MESSAGES_PER_MINUTE = 30

  before_action :authenticate_user!
  before_action :set_team
  before_action :authorize_team_member!
  before_action :set_conversation
  before_action :authorize_participant!

  def index
    messages =
      @conversation
        .messages
        .includes(:sender)
        .order(created_at: :desc)
        .limit(100)
        .to_a
        .reverse

    mark_current_conversation_read!

    render json: {
      messages:
        messages.map {
          |message| message_json(message)
        }
    }, status: :ok
  end

  def create
    other =
      @conversation.other_participant_for(current_user)

    unless other &&
           approved_member?(other) &&
           !other.access_restricted?
      return render json: {
        error: "This teammate is no longer available for messaging."
      }, status: :unprocessable_entity
    end

    if Conversation.blocked_between?(
      first_user: current_user,
      second_user: other
    )
      return render json: {
        error: "This conversation is not available."
      }, status: :forbidden
    end

    if message_rate_limit_reached?
      return render json: {
        error: "You are sending messages too quickly. Please try again shortly."
      }, status: :too_many_requests
    end

    message =
      @conversation.messages.new(message_params)

    message.sender = current_user

    if message.save
      mark_current_conversation_read!
      notify_recipient!(other, message)

      render json: {
        message: message_json(message)
      }, status: :created
    else
      render json: {
        errors: message.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def authorize_team_member!
    return if current_user.team_memberships.exists?(
      team_id: @team.id,
      status: "approved"
    )

    render json: {
      error: "You are not an approved member of this team."
    }, status: :forbidden
  end

  def set_conversation
    @conversation =
      @team.conversations.find(params[:conversation_id])
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

  def message_params
    params
      .require(:message)
      .permit(:body)
  end

  def mark_current_conversation_read!
    @conversation
      .participant_record_for(current_user)
      &.mark_read!
  end

  def message_rate_limit_reached?
    @conversation
      .messages
      .where(sender: current_user)
      .where("created_at >= ?", 1.minute.ago)
      .count >= MAX_MESSAGES_PER_MINUTE
  end

  def notify_recipient!(recipient, message)
    sender_name =
      [current_user.first_name, current_user.last_name]
        .compact
        .join(" ")
        .presence ||
      "A teammate"

    NotificationDelivery.to_user(
      user: recipient,
      title: sender_name,
      message: message.body.truncate(140),
      notification_type: "direct_message",
      actor: current_user,
      featured_user: current_user,
      team: @team,
      conversation: @conversation
    )
  end

  def message_json(message)
    {
      id: message.id,
      conversation_id: message.conversation_id,
      body: message.body,
      sender_id: message.sender_id,
      sender: {
        id: message.sender.id,
        first_name: message.sender.first_name,
        last_name: message.sender.last_name
      },
      created_at: message.created_at,
      updated_at: message.updated_at
    }
  end
end
