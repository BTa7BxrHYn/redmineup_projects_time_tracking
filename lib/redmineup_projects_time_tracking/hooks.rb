# frozen_string_literal: true

module RedmineupProjectsTimeTracking
  class Hooks < Redmine::Hook::ViewListener
    # Add combined budget and history boxes to project overview page
    render_on :view_projects_show_left, partial: 'projects/ptt_combined_box'
  end
end
