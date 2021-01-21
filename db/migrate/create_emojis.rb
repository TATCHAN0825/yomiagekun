class CreateEmojis < ActiveRecord::Migration[6.0]
  def up
    create_table :emojis do |t|
      t.string :character, unique: true, null: false # 文字
      t.string :read, null: false # 読み
    end
  end

  def down
    drop_table :emojis
  end
end
