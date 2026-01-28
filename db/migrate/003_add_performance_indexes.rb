# frozen_string_literal: true

class AddPerformanceIndexes < ActiveRecord::Migration[5.2]
  def change
    add_index :ptt_project_histories,
              [:project_id, :created_at],
              name: 'index_ptt_histories_project_created'

    add_index :ptt_project_histories,
              [:project_id, :field_name],
              name: 'index_ptt_histories_project_field'
  end
end
