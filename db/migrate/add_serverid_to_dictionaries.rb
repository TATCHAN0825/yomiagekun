class AddServeridToDictionaries < ActiveRecord::Migration[6.0]
  def change
    add_column :dictionaries, :serverid, :integer
  end
end
