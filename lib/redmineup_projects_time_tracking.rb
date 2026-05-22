# frozen_string_literal: true

module RedmineupProjectsTimeTracking
end

# Load helper
require_relative '../app/helpers/projects_time_tracking_helper'

# Load model
require_relative '../app/models/ptt_project_history'

# Load patches
require_relative 'redmineup_projects_time_tracking/project_patch'
require_relative 'redmineup_projects_time_tracking/projects_controller_patch'

# Load hooks
require_relative 'redmineup_projects_time_tracking/hooks'

# Apply all patches and helper registrations inside to_prepare so they are
# idempotently re-applied on each code reload (development mode) and correctly
# applied after Zeitwerk has loaded the AR models (production).
#
# Helper is scoped to the three controllers whose views use ptt_* methods,
# instead of the previous global ActionView::Base.include which leaked the
# helper into every view in the application.
Rails.application.config.to_prepare do
  unless Project.included_modules.include?(RedmineupProjectsTimeTracking::ProjectPatch)
    Project.include(RedmineupProjectsTimeTracking::ProjectPatch)
  end

  unless CustomValue.included_modules.include?(RedmineupProjectsTimeTracking::CustomValuePatch)
    CustomValue.include(RedmineupProjectsTimeTracking::CustomValuePatch)
  end

  unless ProjectsController.included_modules.include?(RedmineupProjectsTimeTracking::ProjectsControllerPatch)
    ProjectsController.prepend(RedmineupProjectsTimeTracking::ProjectsControllerPatch)
  end

  # Scope helper to controllers that render ptt_* partials/views:
  #   - ProjectsController: /projects list, /projects/:id show (close guard hook
  #     and combined box hook are rendered in this controller's context)
  #   - AdminController: /admin/projects list (same _list partial as ProjectsController)
  #   - SettingsController: /settings/plugin uses ptt_validate_settings and l()
  # controller.helper is idempotent — safe to call on every reload.
  [ProjectsController, AdminController, SettingsController].each do |controller|
    controller.helper(ProjectsTimeTrackingHelper)
  end
end
