# frozen_string_literal: true

module RedmineupProjectsTimeTracking
  class Hooks < Redmine::Hook::ViewListener
    # Combined box: budget + history in main content area
    render_on :view_projects_show_bottom, partial: 'projects/ptt_combined_box'
  end
end
