class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.references :team, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.text :content
      t.string :post_type
      t.boolean :pinned, default: false, null: false

      t.timestamps
    end
  end
end
