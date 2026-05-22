# frozen_string_literal: true

module ProjectsTimeTrackingHelper
  PTT_HISTORY_LIMIT = 20
  # Maximum number of records loaded in "show all" mode.
  # Uses the limit+1 trick to detect truncation without a separate COUNT query.
  PTT_HISTORY_MAX = 500


  # ===========================================================================
  # Settings and data loading helpers (to reduce code duplication)
  # ===========================================================================

  # Returns plugin settings hash (cached per request)
  def ptt_settings
    @ptt_settings ||= Setting.plugin_redmineup_projects_time_tracking || {}
  end

  # Returns sanitized array of closed status IDs
  def ptt_closed_status_ids
    @ptt_closed_status_ids ||= Array(ptt_settings['closed_status_ids'])
      .filter_map do |id|
        Integer(id)
      rescue ArgumentError, TypeError
        nil
      end
      .reject(&:zero?)
  end

  # Returns sanitized budget custom field ID
  def ptt_budget_custom_field_id
    @ptt_budget_custom_field_id ||= begin
      cf_id = ptt_settings['budget_custom_field_id']
      return nil if cf_id.blank?

      Integer(cf_id)
    rescue ArgumentError, TypeError
      nil
    end
  end

  # Returns budget for a single project
  def ptt_budget_for_project(project)
    return nil unless ptt_budget_custom_field_id
    cv = CustomValue.find_by(
      customized_type: 'Project',
      customized_id: project.id,
      custom_field_id: ptt_budget_custom_field_id
    )
    cv&.value.present? ? cv.value.to_f : nil
  end

  # Returns budgets hash for multiple projects (batch query)
  def ptt_budgets_for_projects(project_ids)
    return {} unless ptt_budget_custom_field_id && project_ids.any?
    CustomValue
      .where(customized_type: 'Project', customized_id: project_ids, custom_field_id: ptt_budget_custom_field_id)
      .pluck(:customized_id, :value)
      .each_with_object({}) { |(pid, val), h| h[pid] = val.to_f if val.present? }
  end

  # Returns issues data for a single project
  def ptt_issues_data_for_project(project)
    data = ptt_issues_data_for_projects([project.id])
    data[project.id] || ptt_empty_issues_data
  end

  # Returns issues data hash for multiple projects (batch query)
  def ptt_issues_data_for_projects(project_ids)
    return {} unless project_ids.any?

    base_query = Issue.visible.where(project_id: project_ids).group(:project_id)
    closed_ids = ptt_closed_status_ids

    if closed_ids.any?
      closed_condition = ActiveRecord::Base.sanitize_sql_array(['status_id IN (?)', closed_ids])
      base_query.pluck(
        :project_id,
        Arel.sql('COALESCE(SUM(estimated_hours), 0)'),
        Arel.sql("COALESCE(SUM(CASE WHEN #{closed_condition} THEN estimated_hours ELSE 0 END), 0)")
      )
    else
      base_query.pluck(
        :project_id,
        Arel.sql('COALESCE(SUM(estimated_hours), 0)'),
        Arel.sql('0')
      )
    end.to_h { |pid, est, closed_est| [pid, { estimated: est.to_f, closed_estimated: closed_est.to_f }] }
  end

  # Returns time spent for a single project
  def ptt_time_spent_for_project(project)
    TimeEntry.visible.where(project_id: project.id).sum(:hours).to_f
  end

  # Returns time spent hash for multiple projects (batch query)
  def ptt_time_spent_for_projects(project_ids)
    return {} unless project_ids.any?
    TimeEntry.visible.where(project_id: project_ids).group(:project_id).sum(:hours)
  end

  # Returns empty issues data hash
  def ptt_empty_issues_data
    { estimated: 0.0, closed_estimated: 0.0 }
  end

  # ===========================================================================
  # History helpers for projects list (optimized for thousands of projects)
  # ===========================================================================

  PTT_HISTORY_PER_FIELD = 5

  # Returns histories grouped by project_id and field_name (batch query).
  # Keeps the most recent PTT_HISTORY_PER_FIELD entries per field per project.
  # Result: { project_id => { 'budget' => [...], 'start_date' => [...] } }
  #
  # No global LIMIT is used: the result set is naturally bounded by the page
  # size (projects shown per page) times the highlightable field count, so a
  # single very active project can no longer starve the others' history.
  def ptt_histories_for_projects(project_ids)
    return {} unless project_ids.any?

    PttProjectHistory
      .where(project_id: project_ids, field_name: PttProjectHistory::HIGHLIGHTABLE_FIELDS)
      .select(:id, :project_id, :field_name, :old_value, :new_value, :created_at)
      .order(created_at: :desc)
      .each_with_object({}) do |h, result|
        per_project = (result[h.project_id] ||= {})
        bucket = (per_project[h.field_name] ||= [])
        bucket << h if bucket.size < PTT_HISTORY_PER_FIELD
      end
  end

  # Returns custom field ID to history field_name mapping
  def ptt_cf_to_field_mapping
    @ptt_cf_to_field_mapping ||= {
      ptt_settings['budget_custom_field_id'].to_s => 'budget',
      ptt_settings['start_date_custom_field_id'].to_s => 'start_date',
      ptt_settings['end_date_custom_field_id'].to_s => 'end_date',
      ptt_settings['comment_custom_field_id'].to_s => 'comment'
    }.compact.reject { |k, _| k.blank? }
  end

  # Checks if custom field has highlightable history for project.
  # Only real changes count (old_value present). Comment field is never highlighted.
  def ptt_cf_has_history?(project_histories, cf_id)
    return false unless project_histories

    field_name = ptt_cf_to_field_mapping[cf_id.to_s]
    return false unless field_name
    return false unless PttProjectHistory::HIGHLIGHTABLE_FIELDS.include?(field_name)

    entries = project_histories[field_name]
    entries&.any? { |h| h.old_value.present? }
  end

  # Returns tooltip with history for custom field (chronological: was -> became)
  def ptt_cf_history_tooltip(project_histories, cf_id)
    return nil unless project_histories
    field_name = ptt_cf_to_field_mapping[cf_id.to_s]
    return nil unless field_name

    entries = project_histories[field_name]
    return nil unless entries&.any?

    # Show only real changes (old_value present) in tooltip
    real_changes = entries.select { |h| h.old_value.present? }
    return nil unless real_changes.any?

    lines = real_changes.map do |h|
      "#{h.formatted_old_value} → #{h.formatted_new_value}"
    end

    "#{l(:ptt_history_changes_label)}\n#{lines.join("\n")}"
  end

  # Returns highlight CSS class if field has history
  def ptt_cf_history_class(project_histories, cf_id)
    ptt_cf_has_history?(project_histories, cf_id) ? 'ptt-history-changed' : nil
  end

  # Computes highlight metadata for a project list column (extracted from the
  # _list partial to keep that overridden core view as close to upstream as
  # possible). Returns { highlight: bool, css_class:, title: }.
  #
  # +can_view+ must be pre-computed by the caller (User.current.allowed_to?(:view_time_entries, entry))
  # to avoid a redundant permission check per column on every project row.
  def ptt_column_history_meta(column, entry, project_histories, tracked_cf_ids, can_view)
    cf_id = column.name.to_s.start_with?('cf_') ? column.name.to_s.sub('cf_', '') : nil
    highlight = cf_id && tracked_cf_ids.include?(cf_id) &&
                can_view &&
                ptt_cf_has_history?(project_histories, cf_id)

    {
      highlight: highlight,
      css_class: highlight ? ptt_cf_history_class(project_histories, cf_id) : nil,
      title: highlight ? ptt_cf_history_tooltip(project_histories, cf_id) : nil
    }
  end

  # ===========================================================================
  # Admin project list: batch open-issue counts (Task B)
  # ===========================================================================

  # Returns a hash of { project_id => open_issue_count } for the given IDs.
  # Uses a single GROUP BY query — no N+1.
  #
  # Counts DIRECT issues only (not the subproject tree). This is intentional:
  # the data attribute is consumed by the JS UX guard only. The authoritative
  # block lives in ProjectsControllerPatch#archive, which counts
  # self_and_descendants. Known compromise: if a project's only open issues
  # are in subprojects the popup will not appear, but the server flash still
  # blocks the action (server guard is authoritative).
  def ptt_open_issue_counts_for_projects(project_ids)
    return {} unless project_ids.any?

    closed_ids = ptt_closed_status_ids
    scope = Issue.where(project_id: project_ids)
    scope = closed_ids.any? ? scope.where.not(status_id: closed_ids) : scope.open
    scope.group(:project_id).count
  end

  # ===========================================================================
  # Settings validation
  # ===========================================================================

  # Validates plugin settings and returns array of warnings
  def ptt_validate_settings(settings)
    warnings = []

    # Batch load all referenced custom fields
    cf_ids = %w[budget start_date end_date comment].filter_map { |f| settings["#{f}_custom_field_id"].presence }
    cf_by_id = CustomField.where(id: cf_ids).index_by { |cf| cf.id.to_s }

    # Validate budget custom field
    budget_cf_id = settings['budget_custom_field_id']
    if budget_cf_id.present?
      cf = cf_by_id[budget_cf_id.to_s]
      if cf.nil?
        warnings << { type: :error, message: l(:ptt_warn_budget_missing) }
      elsif !%w[float int].include?(cf.field_format)
        warnings << { type: :warning, message: l(:ptt_warn_budget_not_numeric, format: cf.field_format) }
      end
    else
      warnings << { type: :info, message: l(:ptt_warn_budget_not_selected) }
    end

    # Validate date custom fields
    %w[start_date end_date].each do |field|
      cf_id = settings["#{field}_custom_field_id"]
      next unless cf_id.present?

      cf = cf_by_id[cf_id.to_s]
      if cf.nil?
        warnings << { type: :error, message: l(:"ptt_warn_#{field}_missing") }
      elsif cf.field_format != 'date'
        warnings << { type: :warning, message: l(:"ptt_warn_#{field}_type") }
      end
    end

    # Validate comment custom field
    comment_cf_id = settings['comment_custom_field_id']
    if comment_cf_id.present?
      cf = cf_by_id[comment_cf_id.to_s]
      if cf.nil?
        warnings << { type: :error, message: l(:ptt_warn_comment_missing) }
      elsif !%w[text string].include?(cf.field_format)
        warnings << { type: :warning, message: l(:ptt_warn_comment_type, format: cf.field_format) }
      end
    end

    # Validate closed statuses
    closed_ids = Array(settings['closed_status_ids']).reject(&:blank?)
    if closed_ids.empty?
      warnings << { type: :warning, message: l(:ptt_warn_no_closed_statuses) }
    else
      existing_ids = IssueStatus.where(id: closed_ids).pluck(:id).map(&:to_s)
      missing = closed_ids.map(&:to_s) - existing_ids
      if missing.any?
        warnings << { type: :error, message: l(:ptt_warn_statuses_deleted, ids: missing.join(', ')) }
      end
    end

    warnings
  end

  # Returns CSS class for validation warning type
  def ptt_validation_css(type)
    case type
    when :error then 'flash error'
    when :warning then 'flash warning'
    else 'flash notice'
    end
  end

  # ===========================================================================
  # Metrics calculation
  # ===========================================================================

  # Calculates project metrics based on budget and issues data
  #
  # @param budget [Float, nil] project budget in hours (B)
  # @param issues_data [Hash] aggregated issues data:
  #   - :estimated [Float] sum of estimated hours for all issues (E_total)
  #   - :closed_estimated [Float] sum of estimated hours for closed issues (E_closed)
  # @param time_spent [Float] total time spent on project (F)
  # @return [Hash, nil] metrics hash or nil if budget is invalid
  def project_metrics(budget, issues_data, time_spent)
    return nil if budget.nil? || budget <= 0

    e_total = issues_data[:estimated] || 0
    e_closed = issues_data[:closed_estimated] || 0
    f = time_spent || 0

    raw = { budget: budget, e_total: e_total, e_closed: e_closed, f: f }

    # Progress = E_closed / E_total × 100%
    progress = e_total > 0 ? (e_closed / e_total) * 100 : 0

    # Spent = F / B × 100%
    spent = (f / budget) * 100

    # CPI/EAC/Variance cannot be computed without actual logged time
    if f == 0 || e_closed == 0
      return {
        progress: progress,
        spent: spent,
        cpi: nil,
        eac: nil,
        variance: nil,
        variance_percent: nil,
        raw: raw,
        incomplete: true
      }
    end

    # CPI = E_closed / F
    cpi = e_closed / f

    # EAC = E_total / CPI
    eac = cpi > 0 ? e_total / cpi : 0

    # Variance = B - EAC
    variance = budget - eac

    # Variance% = (B - EAC) / B × 100%
    variance_percent = (variance / budget) * 100

    {
      progress: progress,
      spent: spent,
      cpi: cpi,
      eac: eac,
      variance: variance,
      variance_percent: variance_percent,
      raw: raw
    }
  end

  # Generates tooltip text for a specific metric
  def metric_tooltip(metric_name, metrics)
    return l(:ptt_no_data_for_calc) if metrics[:incomplete] && %i[cpi eac variance].include?(metric_name)

    raw = metrics[:raw]
    cpi = number_with_precision(metrics[:cpi], precision: 2)

    case metric_name
    when :progress
      l(:ptt_tt_progress,
        e_total: format_metric_hours(raw[:e_total]),
        e_closed: format_metric_hours(raw[:e_closed]),
        result: format_metric_percent(metrics[:progress]))
    when :spent
      l(:ptt_tt_spent,
        f: format_metric_hours(raw[:f]),
        budget: format_metric_hours(raw[:budget]),
        result: format_metric_percent(metrics[:spent]))
    when :cpi
      status = cpi_status(metrics[:cpi])
      l(:ptt_tt_cpi,
        e_closed: format_metric_hours(raw[:e_closed]),
        f: format_metric_hours(raw[:f]),
        cpi: cpi,
        status_icon: status[:icon],
        status_text: status[:text])
    when :eac
      l(:ptt_tt_eac,
        e_total: format_metric_hours(raw[:e_total]),
        cpi: cpi,
        eac: format_metric_hours(metrics[:eac]))
    when :variance
      variance = metrics[:variance]
      status = if variance.nil?
                 l(:ptt_variance_no_data)
               elsif variance > 0
                 l(:ptt_variance_surplus)
               elsif variance < 0
                 l(:ptt_variance_deficit)
               else
                 l(:ptt_variance_exact)
               end
      l(:ptt_tt_variance,
        budget: format_metric_hours(raw[:budget]),
        eac: format_metric_hours(metrics[:eac]),
        variance: format_metric_hours(metrics[:variance]),
        variance_percent: format_metric_percent(metrics[:variance_percent]),
        status: status)
    else
      ''
    end
  end

  # CPI status with icon and text
  def cpi_status(cpi)
    return { icon: '⚪', text: l(:ptt_cpi_status_no_data) } if cpi.nil?

    if cpi >= 1.0
      { icon: '🟢', text: l(:ptt_cpi_status_ok) }
    elsif cpi >= 0.9
      { icon: '🟡', text: l(:ptt_cpi_status_warning) }
    else
      { icon: '🔴', text: l(:ptt_cpi_status_problem) }
    end
  end

  # Formats hours value for display
  def format_metric_hours(value)
    return '—' if value.nil?

    number_with_precision(value, precision: 1, strip_insignificant_zeros: true)
  end

  # Formats percent value for display
  def format_metric_percent(value)
    return '—' if value.nil?

    "#{number_with_precision(value, precision: 1)}%"
  end

  # Returns CSS class for metric based on value thresholds
  def metric_css_class(metric_name, value)
    return nil if value.nil?

    case metric_name
    when :spent
      value > 100 ? 'ptt-overbudget' : nil
    when :cpi
      if value >= 1.0
        'ptt-good'
      elsif value >= 0.9
        'ptt-warning'
      else
        'ptt-overbudget'
      end
    when :variance
      if value < 0
        'ptt-overbudget'
      elsif value > 0
        'ptt-good'
      end
    end
  end
end
