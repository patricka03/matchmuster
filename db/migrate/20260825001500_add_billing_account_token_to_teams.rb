require "securerandom"

class AddBillingAccountTokenToTeams < ActiveRecord::Migration[8.1]
  class MigrationTeam < ActiveRecord::Base
    self.table_name = "teams"
  end

  def up
    add_column :teams,
               :billing_account_token,
               :string

    MigrationTeam.reset_column_information

    MigrationTeam.find_each do |team|
      token =
        loop do
          candidate = SecureRandom.uuid

          break candidate unless
            MigrationTeam.exists?(
              billing_account_token: candidate
            )
        end

      team.update_columns(
        billing_account_token: token
      )
    end

    change_column_null :teams,
                       :billing_account_token,
                       false

    add_index :teams,
              :billing_account_token,
              unique: true
  end

  def down
    remove_index :teams,
                 :billing_account_token

    remove_column :teams,
                  :billing_account_token
  end
end
