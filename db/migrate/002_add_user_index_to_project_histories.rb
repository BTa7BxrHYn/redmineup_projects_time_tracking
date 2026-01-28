# frozen_string_literal: true

class AddUserIndexToProjectHistories < ActiveRecord::Migration[5.2]
  def change
    unless index_exists?(:ptt_project_histories, :user_id, name: 'index_ptt_project_histories_on_user_id')
      add_index :ptt_project_histories, :user_id, name: 'index_ptt_project_histories_on_user_id'
    end
  end
end
