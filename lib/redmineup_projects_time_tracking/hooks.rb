# frozen_string_literal: true

module RedmineupProjectsTimeTracking
  class Hooks < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(context = {})
      safe_join([
        stylesheet_link_tag('projects_time_tracking', plugin: 'redmineup_projects_time_tracking'),
        javascript_include_tag('projects_time_tracking', plugin: 'redmineup_projects_time_tracking')
      ], "\n")
    end

    # Combined box: budget + history in main content area
    render_on :view_projects_show_bottom, partial: 'projects/ptt_combined_box'

    # Close/archive guard: open-issue count + modal popup on project overview
    render_on :view_projects_show_sidebar_bottom, partial: 'hooks/ptt_close_guard'
  end
end
