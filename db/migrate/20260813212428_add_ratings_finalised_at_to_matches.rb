class AddRatingsFinalisedAtToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches,
               :ratings_finalised_at,
               :datetime
  end
end
