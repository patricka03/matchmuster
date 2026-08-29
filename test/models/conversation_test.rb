require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  test "direct conversations only allow the direct type" do
    conversation = Conversation.new(conversation_type: "group")
    conversation.validate
    assert_not_empty conversation.errors[:conversation_type]
  end
end
