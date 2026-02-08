# frozen_string_literal: true

module RedmineupProjectsTimeTracking
  class Hooks < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(context = {})
      stylesheet_link_tag 'projects_time_tracking', plugin: 'redmineup_projects_time_tracking'
    end

    # Combined box: budget + history in main content area
    render_on :view_projects_show_bottom, partial: 'projects/ptt_combined_box'
  end
end
