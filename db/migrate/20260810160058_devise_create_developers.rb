# frozen_string_literal: true

class DeviseCreateDevelopers < ActiveRecord::Migration[8.1]
  def change
    create_table :developers do |t|
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      t.string :reset_password_token
      t.datetime :reset_password_sent_at

      t.datetime :remember_created_at

      t.string :jti, null: false

      t.timestamps null: false
    end

    add_index :developers, :email, unique: true
    add_index :developers, :reset_password_token, unique: true
    add_index :developers, :jti, unique: true
  end
end
