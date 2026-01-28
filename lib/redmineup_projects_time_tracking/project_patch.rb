# frozen_string_literal: true

module RedmineupProjectsTimeTracking
  module ProjectPatch
    extend ActiveSupport::Concern

    included do
      has_many :ptt_histories, class_name: 'PttProjectHistory', dependent: :destroy

      after_save :ptt_track_custom_field_changes
    end

    private

    def ptt_track_custom_field_changes
      return unless User.current&.id

      settings = Setting.plugin_redmineup_projects_time_tracking || {}
      tracked_fields = {
        'budget' => settings['budget_custom_field_id'],
        'start_date' => settings['start_date_custom_field_id'],
        'end_date' => settings['end_date_custom_field_id']
      }.compact_blank

      return if tracked_fields.empty?

      changes_to_record = {}

      tracked_fields.each do |field_key, cf_id|
        next if cf_id.blank?

        cf_id = Integer(cf_id) rescue next
        cv = custom_values.find { |v| v.custom_field_id == cf_id }
        next unless cv

        if cv.previously_new_record?
          # New custom value created
          changes_to_record[field_key] = [nil, cv.value] if cv.value.present?
        elsif cv.saved_change_to_value?
          old_val, new_val = cv.saved_change_to_value
          changes_to_record[field_key] = [old_val, new_val]
        end
      end

      return if changes_to_record.empty?

      PttProjectHistory.record_changes(self, User.current, changes_to_record)
    end
  end
end
