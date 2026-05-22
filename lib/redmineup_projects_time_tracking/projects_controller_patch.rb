# frozen_string_literal: true

module RedmineupProjectsTimeTracking
  # Blocks closing/archiving a project while it (or any subproject) still has
  # open issues. Project#close / #archive use update_all, bypassing model
  # validations and callbacks, so the only reliable interception point is the
  # controller. Prepended so we can call `super` for the normal flow.
  module ProjectsControllerPatch
    def close
      count = @project.ptt_open_issue_count
      return super if count.zero?

      respond_to do |format|
        format.html do
          flash[:error] = l(:ptt_error_close_blocked, count: count)
          redirect_to project_path(@project)
        end
        format.api { render_api_errors(l(:ptt_error_close_blocked, count: count)) }
      end
    end

    def archive
      count = @project.ptt_open_issue_count
      return super if count.zero?

      respond_to do |format|
        format.html do
          flash[:error] = l(:ptt_error_archive_blocked, count: count)
          redirect_to_referer_or admin_projects_path(status: params[:status])
        end
        format.api { render_api_errors(l(:ptt_error_archive_blocked, count: count)) }
      end
    end
  end
end
