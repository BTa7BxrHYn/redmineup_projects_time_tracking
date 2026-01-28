# frozen_string_literal: true

module RedmineupProjectsTimeTracking
end

# Load helper
require_relative '../app/helpers/projects_time_tracking_helper'

# Load hooks
require_relative 'redmineup_projects_time_tracking/hooks'

# Include helper in ActionView
ActionView::Base.include(ProjectsTimeTrackingHelper)
