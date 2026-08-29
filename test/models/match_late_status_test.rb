require "test_helper"

class MatchLateStatusTest < ActiveSupport::TestCase
  test "minutes late accepts exact minute values" do
    status = MatchLateStatus.new(minutes_late: 13)
    status.validate
    assert_empty status.errors[:minutes_late]
  end

  test "minutes late rejects zero" do
    status = MatchLateStatus.new(minutes_late: 0)
    status.validate
    assert_not_empty status.errors[:minutes_late]
  end

  test "minutes late rejects values above five hours" do
    status = MatchLateStatus.new(minutes_late: 301)
    status.validate
    assert_not_empty status.errors[:minutes_late]
  end
end
