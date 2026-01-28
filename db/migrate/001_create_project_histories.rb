# frozen_string_literal: true

class CreateProjectHistories < ActiveRecord::Migration[5.2]
  def change
    create_table :ptt_project_histories do |t|
      t.references :project, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true
      t.string :field_name, null: false
      t.string :old_value
      t.string :new_value
      t.datetime :created_at, null: false
    end

    add_index :ptt_project_histories, :created_at
  end
end
