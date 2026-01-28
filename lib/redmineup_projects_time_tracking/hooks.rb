# frozen_string_literal: true

module RedmineupProjectsTimeTracking
  class Hooks < Redmine::Hook::ViewListener
    # Add metrics box to project overview page
    render_on :view_projects_show_right, partial: 'projects/ptt_metrics_box'

    # Add history box to project overview page (same hook - Dashboard plugin ignores _left)
    render_on :view_projects_show_right, partial: 'projects/ptt_history_box'
  end
end
