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
      Rails.logger.info "[PTT] CustomValue after_save triggered: customized_type=#{customized_type}, custom_field_id=#{custom_field_id}, value=#{value}"

      return unless customized_type == 'Project'
      return unless User.current&.id

      settings = Setting.plugin_redmineup_projects_time_tracking || {}
      tracked_fields = {
        'budget' => settings['budget_custom_field_id'],
        'start_date' => settings['start_date_custom_field_id'],
        'end_date' => settings['end_date_custom_field_id']
      }

      Rails.logger.info "[PTT] tracked_fields=#{tracked_fields.inspect}"

      # Find which field this custom value belongs to
      field_key = tracked_fields.key(custom_field_id.to_s)
      Rails.logger.info "[PTT] field_key=#{field_key.inspect} for custom_field_id=#{custom_field_id}"
      return unless field_key

      # Check if value changed
      if previously_new_record?
        Rails.logger.info "[PTT] previously_new_record, value=#{value}"
        return unless value.present?
        old_val, new_val = nil, value
      elsif saved_change_to_value?
        old_val, new_val = saved_change_to_value
        Rails.logger.info "[PTT] saved_change_to_value: #{old_val} -> #{new_val}"
      else
        Rails.logger.info "[PTT] No change detected"
        return
      end

      project = Project.find_by(id: customized_id)
      return unless project

      Rails.logger.info "[PTT] Recording change for project #{project.id}: #{field_key} #{old_val} -> #{new_val}"
      PttProjectHistory.record_changes(project, User.current, { field_key => [old_val, new_val] })
    end
  end
end
