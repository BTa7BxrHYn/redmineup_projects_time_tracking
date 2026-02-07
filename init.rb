# frozen_string_literal: true

Redmine::Plugin.register :redmineup_projects_time_tracking do
  name 'Projects Time Tracking'
  author 'dread@altuera.com'
  description 'Time tracking columns for projects table with budget metrics and history'
  version '0.3.2'
  author_url 'mailto:dread@altuera.com'

  requires_redmine version_or_higher: '5.1'

  settings(
    default: {
      'budget_custom_field_id' => '',
      'start_date_custom_field_id' => '',
      'end_date_custom_field_id' => '',
      'comment_custom_field_id' => '',
      'closed_status_ids' => []
    },
    partial: 'settings/redmineup_projects_time_tracking'
  )
end

require_relative 'lib/redmineup_projects_time_tracking'
