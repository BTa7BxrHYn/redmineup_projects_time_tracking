# frozen_string_literal: true

module RedmineupProjectsTimeTracking
  class Hooks < Redmine::Hook::ViewListener
    # Add metrics box to project overview page (right sidebar)
    render_on :view_projects_show_right, partial: 'projects/ptt_metrics_box'
  end
end
