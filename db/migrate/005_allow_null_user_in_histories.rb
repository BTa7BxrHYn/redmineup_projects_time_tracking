# frozen_string_literal: true

class AllowNullUserInHistories < ActiveRecord::Migration[5.2]
  def up
    change_column_null :ptt_project_histories, :user_id, true
  end

  def down
    change_column_null :ptt_project_histories, :user_id, false
  end
end
