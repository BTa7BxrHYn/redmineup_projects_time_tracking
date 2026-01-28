# frozen_string_literal: true

module RedmineupProjectsTimeTracking
  class Hooks < Redmine::Hook::ViewListener
    # Combined box: budget + history
    # view_projects_show_sidebar_bottom — works with both standard Redmine and additionals plugin
    render_on :view_projects_show_sidebar_bottom, partial: 'projects/ptt_combined_box'
  end
end
