class AddFormationToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :formation, :string
  end
end
