class CreateItems < ActiveRecord::Migration
  def self.up
    create_table :items do |t|
      t.column :title, :string
      t.column :url, :string
      t.column :description, :string
      t.column :category, :string
      t.column :thumbnail, :string      
      t.timestamps
    end
    
    create_table :items_tags, :id => false do |t|
      t.column :item_id, :integer
      t.column :tag_id, :integer
      end
  end

  def self.down
    drop_table :items
    drop_table :items_tags
  end
end
