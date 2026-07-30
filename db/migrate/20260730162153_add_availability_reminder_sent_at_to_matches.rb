class AddAvailabilityReminderSentAtToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :availability_reminder_sent_at, :datetime
  end
end
