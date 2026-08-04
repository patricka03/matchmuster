class AddDescriptionToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :description, :text
  end
end
