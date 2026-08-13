class CreateLegalAcceptances < ActiveRecord::Migration[8.1]
  def change
    create_table :legal_acceptances do |t|
      t.references :user, null: false, foreign_key: true

      t.string :document_type, null: false
      t.string :document_version, null: false
      t.datetime :accepted_at, null: false

      t.timestamps
    end

    add_index(
      :legal_acceptances,
      [:user_id, :document_type, :document_version],
      unique: true,
      name: "index_legal_acceptances_unique"
    )
  end
end
