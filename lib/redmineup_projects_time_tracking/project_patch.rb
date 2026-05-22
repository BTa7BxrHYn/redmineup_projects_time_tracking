# frozen_string_literal: true

module RedmineupProjectsTimeTracking
  module ProjectPatch
    extend ActiveSupport::Concern

    included do
      # delete_all is safe here: PttProjectHistory has no destroy callbacks,
      # and bulk deletion is significantly faster than per-record destroy calls.
      has_many :ptt_histories, class_name: 'PttProjectHistory', dependent: :delete_all
    end

    # Number of open (not closed) issues in this project and all its
    # subprojects. Used to block closing/archiving a project that still has
    # unfinished work. Counts all issues (not only those visible to the current
    # user), since closing/archiving is an administrative action.
    #
    # Definition of "open" is kept consistent with the plugin's progress metrics:
    #   - If closed_status_ids are configured in plugin settings, issues whose
    #     status_id is NOT in that list are counted as open.
    #   - Otherwise falls back to the Redmine core Issue.open scope
    #     (is_closed = false on the issue status record).
    def ptt_open_issue_count
      settings = Setting.plugin_redmineup_projects_time_tracking || {}
      closed_ids = Array(settings['closed_status_ids'])
                   .filter_map { |id| Integer(id) rescue nil }
                   .reject(&:zero?)

      scope = Issue.where(project_id: self_and_descendants)
      closed_ids.any? ? scope.where.not(status_id: closed_ids).count : scope.open.count
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

      project = customized
      return unless project

      PttProjectHistory.record_changes(project, User.current, { field_key => [old_val, new_val] })
    end
  end
end
