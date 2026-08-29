class CreateSocialIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :social_identities do |t|
      t.references :user,
                   null: false,
                   foreign_key: {
                     on_delete: :cascade
                   }
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :email
      t.timestamps
    end

    add_index :social_identities,
              %i[provider uid],
              unique: true

    add_index :social_identities,
              %i[user_id provider],
              unique: true
  end
end
