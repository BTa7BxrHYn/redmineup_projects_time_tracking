# frozen_string_literal: true

module RedmineupProjectsTimeTracking
end

# Load helper
require_relative '../app/helpers/projects_time_tracking_helper'

# Load model
require_relative '../app/models/ptt_project_history'

# Load patches
require_relative 'redmineup_projects_time_tracking/project_patch'

# Load hooks
require_relative 'redmineup_projects_time_tracking/hooks'

# Include helper in ActionView
ActionView::Base.include(ProjectsTimeTrackingHelper)

# Apply patches
Rails.application.config.to_prepare do
  unless Project.included_modules.include?(RedmineupProjectsTimeTracking::ProjectPatch)
    Project.include(RedmineupProjectsTimeTracking::ProjectPatch)
  end

  unless CustomValue.included_modules.include?(RedmineupProjectsTimeTracking::CustomValuePatch)
    CustomValue.include(RedmineupProjectsTimeTracking::CustomValuePatch)
  end
end
