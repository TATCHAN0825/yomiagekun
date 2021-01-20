class CreateDictionaries < ActiveRecord::Migration[6.0]
  def up
    create_table :dictionaries do |t|
      t.string :before
      t.string :after

    end
  end

  def down
    drop_table :dictionaries
  end
end
