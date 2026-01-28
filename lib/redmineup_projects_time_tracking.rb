# frozen_string_literal: true

module RedmineupProjectsTimeTracking
end

# Load helper
require_relative '../app/helpers/projects_time_tracking_helper'

# Include helper in ActionView
ActionView::Base.include(ProjectsTimeTrackingHelper)
