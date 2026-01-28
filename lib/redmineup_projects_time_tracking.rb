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

# Apply patches using to_prepare for reloading support
Rails.logger.info "[PTT] Loading plugin patches"

# Apply immediately at load time (works in production)
if defined?(Project)
  Rails.logger.info "[PTT] Project is defined, patching immediately"
  unless Project.included_modules.include?(RedmineupProjectsTimeTracking::ProjectPatch)
    Project.include(RedmineupProjectsTimeTracking::ProjectPatch)
  end
end

if defined?(CustomValue)
  Rails.logger.info "[PTT] CustomValue is defined, patching immediately"
  unless CustomValue.included_modules.include?(RedmineupProjectsTimeTracking::CustomValuePatch)
    CustomValue.include(RedmineupProjectsTimeTracking::CustomValuePatch)
    Rails.logger.info "[PTT] CustomValue callbacks after patch: #{CustomValue._save_callbacks.map(&:filter).inspect}"
  end
end

# Also register for reloading in development mode
Rails.application.config.to_prepare do
  Rails.logger.info "[PTT] to_prepare block executing"

  unless Project.included_modules.include?(RedmineupProjectsTimeTracking::ProjectPatch)
    Rails.logger.info "[PTT] Including ProjectPatch into Project (to_prepare)"
    Project.include(RedmineupProjectsTimeTracking::ProjectPatch)
  end

  unless CustomValue.included_modules.include?(RedmineupProjectsTimeTracking::CustomValuePatch)
    Rails.logger.info "[PTT] Including CustomValuePatch into CustomValue (to_prepare)"
    CustomValue.include(RedmineupProjectsTimeTracking::CustomValuePatch)
  end
end
