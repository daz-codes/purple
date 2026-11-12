class CreateUsers < ActiveRecord::Migration[8.2]
  def change
    enable_extension "citext"

    create_table :users do |t|
      t.citext :email_address, null: false
      t.string :password_digest, null: false
      t.citext :display_name, null: false
      t.datetime :confirmed_at
      t.boolean :admin, null: false, default: false

      t.timestamps
    end
    add_index :users, :email_address, unique: true
    add_index :users, :display_name, unique: true
  end
end
