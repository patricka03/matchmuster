require "test_helper"

class TeamFinanceEntryTest < ActiveSupport::TestCase
  test "entry type accepts income and expense" do
    income = TeamFinanceEntry.new(entry_type: "income")
    expense = TeamFinanceEntry.new(entry_type: "expense")

    income.validate
    expense.validate

    assert_empty income.errors[:entry_type]
    assert_empty expense.errors[:entry_type]
  end

  test "amount must be positive" do
    entry = TeamFinanceEntry.new(amount_pence: 0)
    entry.validate
    assert_not_empty entry.errors[:amount_pence]
  end
end
