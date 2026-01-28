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
Rails.logger.info "[PTT] Registering to_prepare callback"

Rails.application.config.to_prepare do
  Rails.logger.info "[PTT] to_prepare block executing"

  unless Project.included_modules.include?(RedmineupProjectsTimeTracking::ProjectPatch)
    Rails.logger.info "[PTT] Including ProjectPatch into Project"
    Project.include(RedmineupProjectsTimeTracking::ProjectPatch)
  end

  unless CustomValue.included_modules.include?(RedmineupProjectsTimeTracking::CustomValuePatch)
    Rails.logger.info "[PTT] Including CustomValuePatch into CustomValue"
    CustomValue.include(RedmineupProjectsTimeTracking::CustomValuePatch)
  end

  Rails.logger.info "[PTT] CustomValue callbacks: #{CustomValue._save_callbacks.map(&:filter).inspect}"
end
