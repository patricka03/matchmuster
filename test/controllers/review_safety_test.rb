require "test_helper"

class ReviewSafetyTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @manager = member("manager", "manager")
    @manager.update_column(:manager_verification_status, "approved")
    @player = member("player")
    @outsider = member("outsider")
    @team = Team.create!(name: "Safety Test FC", owner_user: @manager)
    [@manager, @player, @outsider].each do |user|
      TeamMembership.create!(team: @team, user: user, status: "approved",
        role: user == @manager ? "manager" : "player", preferred_position: "CM")
    end
    @conversation = Conversation.direct_between!(team: @team, first_user: @manager, second_user: @player)
    @message = @conversation.messages.create!(sender: @manager, body: "A message for the safety review")
    @headers = headers_for(@player)
    clear_enqueued_jobs
  end

  test "recipient can report a private message and notify moderators" do
    assert_enqueued_with(job: ModerationAlertJob) do
      assert_difference "Report.count", 1 do
        report_message(reason: "harassment", reported_user_id: @outsider.id)
      end
    end
    assert_response :created
    report = Report.order(:id).last
    assert_equal @manager, report.reported_user, "The server must derive the actual author"
    assert_equal @message, report.reportable
    assert_equal @message.body, report.content_snapshot.fetch("body")

    assert_no_difference "Report.count" do
      report_message(reason: "harassment")
    end
    assert_response :ok
  end

  test "another team member cannot report a private conversation they do not participate in" do
    @headers = headers_for(@outsider)
    assert_no_difference "Report.count" do
      report_message(reason: "harassment")
    end
    assert_response :forbidden
  end

  test "both legacy report categories remain accepted" do
    { "hate_speech" => "discrimination", "sexual_content" => "inappropriate_content" }.each do |input, expected|
      report_message(reason: input)
      assert_response :created
      report = Report.order(:id).last
      assert_equal expected, report.reason
      report.update!(status: "dismissed")
    end
  end

  test "other reports require an explanation" do
    assert_no_difference "Report.count" do
      report_message(reason: "other")
    end
    assert_response :unprocessable_entity
  end

  test "block reports the source and hides both directions without deleting unrelated chats" do
    unrelated = Conversation.direct_between!(team: @team, first_user: @player, second_user: @outsider)
    assert_enqueued_with(job: ModerationAlertJob) do
      assert_difference ["UserBlock.count", "Report.count"], 1 do
        block_manager(reportable_type: "Message", reportable_id: @message.id)
      end
    end
    assert_response :created
    report = Report.order(:id).last
    assert_equal "user_block", report.content_snapshot["trigger"]
    assert_equal @message.body, report.content_snapshot["body"]

    get "/teams/#{@team.id}/conversations", headers: @headers, as: :json
    assert_response :ok
    assert_equal [unrelated.id], response.parsed_body.fetch("conversations").pluck("id")
    assert_blocked_routes(@headers)
    assert_blocked_routes(headers_for(@manager))

    get "/teams/#{@team.id}/conversations/recipients", headers: @headers, as: :json
    assert_response :ok
    assert_not_includes response.parsed_body.fetch("recipients").pluck("id"), @manager.id

    assert_no_difference ["UserBlock.count", "Report.count"] do
      block_manager(reportable_type: "Message", reportable_id: @message.id)
    end
    assert_response :ok
  end

  test "block without source content still creates a developer report" do
    assert_difference "Report.count", 1 do
      block_manager
    end
    assert_response :created
    assert_equal @manager, Report.order(:id).last.reported_user
  end

  test "blocking after reporting the same message still alerts moderators to the block" do
    report_message(reason: "harassment")
    clear_enqueued_jobs
    assert_enqueued_with(job: ModerationAlertJob) do
      assert_difference "Report.count", 1 do
        block_manager(reportable_type: "Message", reportable_id: @message.id)
      end
    end
    assert_response :created
    assert_equal "user_block", Report.order(:id).last.content_snapshot["trigger"]
  end

  test "block cannot attach someone else's private content" do
    private_chat = Conversation.direct_between!(team: @team, first_user: @manager, second_user: @outsider)
    private_message = private_chat.messages.create!(sender: @manager, body: "Private to the other member")
    assert_no_difference ["UserBlock.count", "Report.count"] do
      block_manager(reportable_type: "Message", reportable_id: private_message.id)
    end
    assert_response :forbidden
  end

  test "block cannot attach content by a different author" do
    assert_no_difference ["UserBlock.count", "Report.count"] do
      post "/user_blocks", headers: @headers, as: :json, params: { user_block: {
        blocked_user_id: @outsider.id, reportable_type: "Message", reportable_id: @message.id
      } }
    end
    assert_response :forbidden
  end

  test "unblocking restores access while preserving the moderation record" do
    block_manager
    block = @player.initiated_blocks.find_by!(blocked_user: @manager)
    assert_no_difference "Report.count" do
      delete "/user_blocks/#{block.id}", headers: @headers, as: :json
    end
    assert_response :no_content
    get messages_path, headers: @headers, as: :json
    assert_response :ok
    assert_equal [@message.id], response.parsed_body.fetch("messages").pluck("id")
  end

  test "message evidence survives sender editing and deleting it" do
    report_message(reason: "harassment")
    report = Report.order(:id).last
    original = @message.body
    @message.update!(body: "Edited after reporting")
    assert_equal original, report.reload.content_snapshot["body"]
    @message.destroy!
    assert_nil report.reload.reportable
    assert_equal original, report.content_snapshot["body"]
  end

  test "moderators can remove a reported message without losing evidence" do
    report_message(reason: "harassment")
    report = Report.order(:id).last
    developer = Developer.create!(email: "safety-moderator@example.com", password: "Password123!")
    ModerationService.new(report: report, developer: developer).remove_content!(notes: "Safety test removal")
    assert_not Message.exists?(@message.id)
    assert_equal "actioned", report.reload.status
    assert_equal "A message for the safety review", report.content_snapshot["body"]
  end

  test "existing content filter also covers creation and editing of messages" do
    assert_no_difference "Message.count" do
      post messages_path, headers: @headers, as: :json,
        params: { message: { body: "go kill yourself" } }
    end
    assert_response :unprocessable_entity
    patch "#{messages_path}/#{@message.id}", headers: headers_for(@manager), as: :json,
      params: { message: { body: "go kill yourself" } }
    assert_response :unprocessable_entity
    assert_equal "A message for the safety review", @message.reload.body
  end

  test "blocking hides old post and message notifications while operational alerts remain" do
    post_record = @team.posts.create!(user: @manager, title: "Team note", content: "Review post", post_type: "general")
    notice = @player.notifications.create!(title: "Message", message: @message.body,
      notification_type: "direct_message", actor: @manager, conversation: @conversation)
    post_notice = @player.notifications.create!(title: "Post", message: "Review post",
      notification_type: "post_created", post: post_record)
    operational = @player.notifications.create!(title: "Fixture", message: "Kickoff changed",
      notification_type: "fixture_updated", actor: @manager)
    block_manager(reportable_type: "Post", reportable_id: post_record.id)
    get "/notifications", headers: @headers, as: :json
    assert_response :ok
    ids = response.parsed_body.pluck("id")
    assert_not_includes ids, notice.id
    assert_not_includes ids, post_notice.id
    assert_includes ids, operational.id
    get "/teams/#{@team.id}/posts/#{post_record.id}", headers: @headers, as: :json
    assert_response :not_found
  end

  test "blocked authors do not trigger another native content push" do
    block_manager
    calls = []
    original = FirebasePushService.method(:to_user)
    FirebasePushService.define_singleton_method(:to_user) { |**args| calls << args; 1 }
    @player.notifications.create!(title: "Message", message: "Blocked content",
      notification_type: "direct_message", actor: @manager, conversation: @conversation)
    assert_empty calls
    @player.notifications.create!(title: "Fixture", message: "Kickoff changed",
      notification_type: "fixture_updated", actor: @manager)
    assert_equal 1, calls.length
  ensure
    FirebasePushService.define_singleton_method(:to_user, original) if original
  end

  test "moderation email identifies report without copying private content" do
    report_message(reason: "harassment")
    report = Report.order(:id).last
    mail = ModerationMailer.report_received(report.id)
    assert_includes mail.subject, report.id.to_s
    assert_not_includes mail.body.to_s, @message.body
    assert_not_includes mail.body.to_s, @player.email
  end

  test "moderators can remove a post with notifications attached" do
    content = @team.posts.create!(user: @manager, title: "Moderation test", content: "Review this post", post_type: "general")
    notice = @player.notifications.create!(title: "Post", message: content.content,
      notification_type: "post_created", post: content, actor: @manager)
    report = @player.submitted_reports.create!(reported_user: @manager, reportable: content, reason: "harassment")
    developer = Developer.create!(email: "post-moderator@example.com", password: "Password123!")
    ModerationService.new(report: report, developer: developer).remove_content!(notes: "Remove reviewed post")
    assert_not Post.exists?(content.id)
    assert_not Notification.exists?(notice.id)
    assert_equal "Review this post", report.reload.content_snapshot["content"]
  end

  private


  def member(name, role = "player")
    User.create!(first_name: "Safety", last_name: name, email: "safety-#{name}@example.com",
      account_type: role, password: "Password123!", password_confirmation: "Password123!")
  end

  def headers_for(user)
    post "/users/sign_in", params: { user: { email: user.email, password: "Password123!" } }, as: :json
    assert_response :ok
    { "Authorization" => response.headers.fetch("Authorization") }
  end

  def messages_path
    "/teams/#{@team.id}/conversations/#{@conversation.id}/messages"
  end

  def report_message(**attributes)
    post "/reports", headers: @headers, as: :json, params: { report: {
      reportable_type: "Message", reportable_id: @message.id, **attributes
    } }
  end

  def block_manager(**attributes)
    post "/user_blocks", headers: @headers, as: :json, params: { user_block: {
      blocked_user_id: @manager.id, **attributes
    } }
  end

  def assert_blocked_routes(headers)
    get "/teams/#{@team.id}/conversations/#{@conversation.id}", headers: headers, as: :json
    assert_response :forbidden
    get messages_path, headers: headers, as: :json
    assert_response :forbidden
    assert_no_difference "Message.count" do
      post messages_path, headers: headers, as: :json, params: { message: { body: "Blocked attempt" } }
    end
    assert_response :forbidden
    patch "#{messages_path}/#{@message.id}", headers: headers, as: :json, params: { message: { body: "Edited attempt" } }
    assert_response :forbidden
  end
end
