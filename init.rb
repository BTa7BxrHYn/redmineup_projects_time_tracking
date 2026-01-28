# frozen_string_literal: true

Redmine::Plugin.register :redmineup_projects_time_tracking do
  name 'Redmineup Projects Time Tracking plugin'
  author 'redmineup.com'
  description 'Time tracking columns for projects table with budget metrics and history'
  version '0.3.0'
  author_url 'mailto:support@redmineup.com'

  requires_redmine version_or_higher: '5.1'

  settings(
    default: {
      'budget_custom_field_id' => '',
      'start_date_custom_field_id' => '',
      'end_date_custom_field_id' => '',
      'closed_status_ids' => []
    },
    partial: 'settings/redmineup_projects_time_tracking'
  )
end

require_relative 'lib/redmineup_projects_time_tracking'
