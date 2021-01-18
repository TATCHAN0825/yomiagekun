class CreatePrefixes < ActiveRecord::Migration[6.0]
  def up
    create_table :prefixes do |t|
      t.string :prefix
    end
  end

  def down
    drop_table :prefixes
  end
end
