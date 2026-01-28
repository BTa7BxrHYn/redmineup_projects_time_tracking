# frozen_string_literal: true

module RedmineupProjectsTimeTracking
  class Hooks < Redmine::Hook::ViewListener
    # Budget and history side by side in main content area
    render_on :view_projects_show_left, partial: 'projects/ptt_combined_box'

    # Fallback: also try sidebar
    # render_on :view_projects_show_right, partial: 'projects/ptt_combined_box'
  end
end
