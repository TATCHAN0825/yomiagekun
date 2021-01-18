class InitialSchema < ActiveRecord::Migration[6.0]
  def up
    create_table :users do |t|
      t.string :voice
      t.string :emotion
      t.float :speed
      t.float :tone
    end
  end

  def down
    drop_table :users
  end
end
