# frozen_string_literal: true

class ChangeHistoryValuesToText < ActiveRecord::Migration[5.2]
  def up
    change_column :ptt_project_histories, :old_value, :text
    change_column :ptt_project_histories, :new_value, :text
  end

  def down
    # WARNING: reverting to string will truncate values longer than 255 chars
    change_column :ptt_project_histories, :old_value, :string
    change_column :ptt_project_histories, :new_value, :string
  end
end
