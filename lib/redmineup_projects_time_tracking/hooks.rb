# frozen_string_literal: true

module RedmineupProjectsTimeTracking
  class Hooks < Redmine::Hook::ViewListener
    # Combined box: budget (left) + history (right) side by side
    render_on :view_projects_show_right, partial: 'projects/ptt_combined_box'
  end
end
