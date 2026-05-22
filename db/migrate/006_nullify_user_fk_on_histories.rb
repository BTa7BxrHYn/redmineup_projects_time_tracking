# frozen_string_literal: true

# The original FK (migration 001) had no ON DELETE behaviour, while migration
# 005 made user_id nullable and the UI already renders "[deleted]" for orphaned
# rows. Without ON DELETE SET NULL, deleting a user that has history rows would
# raise a foreign key violation. Recreate the FK with on_delete: :nullify so the
# "user is nil" state the views expect is actually reachable.
class NullifyUserFkOnHistories < ActiveRecord::Migration[5.2]
  def up
    if foreign_key_exists?(:ptt_project_histories, :users)
      remove_foreign_key :ptt_project_histories, :users
    end
    add_foreign_key :ptt_project_histories, :users, on_delete: :nullify
  end

  def down
    if foreign_key_exists?(:ptt_project_histories, :users)
      remove_foreign_key :ptt_project_histories, :users
    end
    add_foreign_key :ptt_project_histories, :users
  end
end
