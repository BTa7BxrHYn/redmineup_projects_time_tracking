# frozen_string_literal: true

module RedmineupProjectsTimeTracking
  module ProjectPatch
    extend ActiveSupport::Concern

    included do
      has_many :ptt_histories, class_name: 'PttProjectHistory', dependent: :destroy
    end
  end

  module CustomValuePatch
    extend ActiveSupport::Concern

    included do
      after_save :ptt_track_project_custom_field_change
    end

    private

    def ptt_track_project_custom_field_change
      return unless customized_type == 'Project'
      return unless User.current&.logged?

      settings = Setting.plugin_redmineup_projects_time_tracking || {}
      tracked_fields = {
        'budget' => settings['budget_custom_field_id'],
        'start_date' => settings['start_date_custom_field_id'],
        'end_date' => settings['end_date_custom_field_id'],
        'comment' => settings['comment_custom_field_id']
      }

      # Find which field this custom value belongs to
      field_key = tracked_fields.key(custom_field_id.to_s)
      return unless field_key

      # Check if value changed
      if previously_new_record?
        return unless value.present?
        old_val, new_val = nil, value
      elsif saved_change_to_value?
        old_val, new_val = saved_change_to_value
      else
        return
      end

      project = Project.find_by(id: customized_id)
      return unless project

      PttProjectHistory.record_changes(project, User.current, { field_key => [old_val, new_val] })
    end
  end
end
