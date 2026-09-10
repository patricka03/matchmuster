class AddContentSnapshotToReports < ActiveRecord::Migration[8.1]
  def change
    add_column :reports, :content_snapshot, :jsonb, default: {}, null: false
  end
end
