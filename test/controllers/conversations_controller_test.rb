require "test_helper"

class ConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = create_user(
      email: "conversation-manager@example.com",
      account_type: "manager"
    )

    @manager.update_column(
      :manager_verification_status,
      "approved"
    )

    @player = create_user(
      email: "conversation-player@example.com",
      account_type: "player"
    )

    @team = Team.create!(
      name: "Conversation Test FC",
      owner_user: @manager
    )

    add_membership(
      user: @manager,
      role: "manager"
    )

    add_membership(
      user: @player,
      role: "player"
    )

    @headers = auth_headers(@manager)
  end

  test "approved member can load an empty inbox" do
    get "/teams/#{@team.id}/conversations",
        headers: @headers,
        as: :json

    assert_response :ok

    payload = JSON.parse(response.body)

    assert_equal [], payload.fetch("conversations")
  end

  test "approved member can load eligible recipients" do
    get "/teams/#{@team.id}/conversations/recipients",
        headers: @headers,
        as: :json

    assert_response :ok

    recipients =
      JSON
        .parse(response.body)
        .fetch("recipients")

    assert_equal [@player.id], recipients.pluck("id")
  end

  test "approved member can create and reload a direct conversation" do
    assert_difference "Conversation.count", 1 do
      post "/teams/#{@team.id}/conversations",
           params: {
             conversation: {
               recipient_id: @player.id
             }
           },
           headers: @headers,
           as: :json
    end

    assert_response :ok

    conversation_id =
      JSON
        .parse(response.body)
        .dig("conversation", "id")

    get "/teams/#{@team.id}/conversations",
        headers: @headers,
        as: :json

    assert_response :ok

    conversations =
      JSON
        .parse(response.body)
        .fetch("conversations")

    assert_equal [conversation_id], conversations.pluck("id")
    assert_equal @player.id,
                 conversations.first.dig("other_user", "id")
  end

  private

  def create_user(email:, account_type:)
    User.create!(
      first_name: "Conversation",
      last_name: account_type.capitalize,
      account_type: account_type,
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!"
    )
  end

  def add_membership(user:, role:)
    TeamMembership.create!(
      team: @team,
      user: user,
      role: role,
      status: "approved",
      preferred_position: "CM"
    )
  end

  def auth_headers(user)
    post "/users/sign_in",
         params: {
           user: {
             email: user.email,
             password: "Password123!"
           }
         },
         as: :json

    assert_response :ok

    {
      "Authorization" =>
        response.headers.fetch("Authorization")
    }
  end
end
