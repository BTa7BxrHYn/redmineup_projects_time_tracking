# frozen_string_literal: true

module RedmineupProjectsTimeTracking
  def self.setup
    Rails.application.config.to_prepare do
      ApplicationController.helper(ProjectsTimeTrackingHelper)
    end
  end
end

RedmineupProjectsTimeTracking.setup
