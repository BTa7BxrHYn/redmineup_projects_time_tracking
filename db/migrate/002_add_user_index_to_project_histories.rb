# frozen_string_literal: true

class AddUserIndexToProjectHistories < ActiveRecord::Migration[5.2]
  def up
    unless index_exists?(:ptt_project_histories, :user_id, name: 'index_ptt_project_histories_on_user_id')
      add_index :ptt_project_histories, :user_id, name: 'index_ptt_project_histories_on_user_id'
    end
  end

  def down
    if index_exists?(:ptt_project_histories, :user_id, name: 'index_ptt_project_histories_on_user_id')
      remove_index :ptt_project_histories, name: 'index_ptt_project_histories_on_user_id'
    end
  end
end
