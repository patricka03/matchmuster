class AddCancelledAtToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :cancelled_at, :datetime
    add_index :matches, :cancelled_at
  end
end
