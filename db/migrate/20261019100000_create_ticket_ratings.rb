class CreateTicketRatings < ActiveRecord::Migration[7.0]
  def change
    unless table_exists?(:ticket_ratings)
      create_table :ticket_ratings do |t|
        t.references :ticket, null: false, foreign_key: true, index: true
        t.references :customer, null: false, foreign_key: { to_table: :users }, index: true
        t.references :agent, null: false, foreign_key: { to_table: :users }, index: true
        t.integer :rating, null: false, limit: 2
        t.text :comment
        t.timestamps
      end
      add_index :ticket_ratings, [:ticket_id, :agent_id], unique: true
    end

    unless column_exists?(:users, :average_rating)
      add_column :users, :average_rating, :decimal, precision: 3, scale: 2, default: 0.0
      add_index :users, :average_rating
    end

    unless column_exists?(:users, :total_ratings)
      add_column :users, :total_ratings, :integer, default: 0
    end
  end
end
