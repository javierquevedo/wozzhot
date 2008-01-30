class CreateTagstats < ActiveRecord::Migration
  def self.up
    create_table :tagstats do |t|
      t.column :title, :string
      t.column :karma, :int
      
      t.timestamps
    end
  end

  def self.down
    drop_table :tagstats
  end
end
