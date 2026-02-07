# frozen_string_literal: true

module ProjectsTimeTrackingHelper
  PTT_HISTORY_LIMIT = 20

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

  # Returns histories grouped by project_id and field_name (batch query)
  # Limits to last 5 entries per field for performance
  # Result: { project_id => { 'budget' => [...], 'start_date' => [...] } }
  def ptt_histories_for_projects(project_ids)
    return {} unless project_ids.any?

    # Limit total records to avoid memory issues (5 entries * 3 fields * projects)
    max_records = project_ids.size * 15

    PttProjectHistory
      .where(project_id: project_ids)
      .select(:id, :project_id, :field_name, :old_value, :new_value, :created_at)
      .order(created_at: :desc)
      .limit(max_records)
      .each_with_object({}) do |h, result|
        result[h.project_id] ||= {}
        result[h.project_id][h.field_name] ||= []
        # Limit to 5 entries per field for tooltip
        result[h.project_id][h.field_name] << h if result[h.project_id][h.field_name].size < 5
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

  # Formats value for history display based on field type
  def ptt_format_history_value(value, field_name)
    return '—' if value.blank?

    case field_name
    when 'start_date', 'end_date'
      begin
        Date.parse(value).strftime('%d.%m.%Y')
      rescue ArgumentError, TypeError
        value
      end
    when 'budget'
      "#{value} ч"
    when 'comment'
      value.to_s.truncate(100)
    else
      value
    end
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
      old_val = ptt_format_history_value(h.old_value, field_name)
      new_val = ptt_format_history_value(h.new_value, field_name)
      "#{old_val} → #{new_val}"
    end

    "История изменений:\n#{lines.join("\n")}"
  end

  # Returns highlight style if field has history
  def ptt_cf_history_style(project_histories, cf_id)
    ptt_cf_has_history?(project_histories, cf_id) ? 'background-color: #ffffcc;' : nil
  end

  # ===========================================================================
  # Settings validation
  # ===========================================================================

  # Validates plugin settings and returns array of warnings
  def ptt_validate_settings(settings)
    warnings = []

    # Validate budget custom field
    budget_cf_id = settings['budget_custom_field_id']
    if budget_cf_id.present?
      cf = CustomField.find_by(id: budget_cf_id)
      if cf.nil?
        warnings << { type: :error, message: 'Выбранное поле бюджета не существует' }
      elsif !%w[float int].include?(cf.field_format)
        warnings << { type: :warning, message: "Поле бюджета должно быть числовым (текущий тип: #{cf.field_format})" }
      end
    else
      warnings << { type: :info, message: 'Поле бюджета не выбрано - метрики не будут отображаться' }
    end

    # Validate date custom fields
    %w[start_date end_date].each do |field|
      cf_id = settings["#{field}_custom_field_id"]
      next unless cf_id.present?
      cf = CustomField.find_by(id: cf_id)
      if cf.nil?
        warnings << { type: :error, message: "Выбранное поле #{field == 'start_date' ? 'начала' : 'окончания'} проекта не существует" }
      elsif cf.field_format != 'date'
        warnings << { type: :warning, message: "Поле #{field == 'start_date' ? 'начала' : 'окончания'} должно быть типа 'дата'" }
      end
    end

    # Validate comment custom field
    comment_cf_id = settings['comment_custom_field_id']
    if comment_cf_id.present?
      cf = CustomField.find_by(id: comment_cf_id)
      if cf.nil?
        warnings << { type: :error, message: 'Выбранное поле комментария не существует' }
      elsif !%w[text string].include?(cf.field_format)
        warnings << { type: :warning, message: "Поле комментария должно быть текстовым (текущий тип: #{cf.field_format})" }
      end
    end

    # Validate closed statuses
    closed_ids = Array(settings['closed_status_ids']).reject(&:blank?)
    if closed_ids.empty?
      warnings << { type: :warning, message: 'Не выбраны статусы "Закрыто" - прогресс всегда будет 0%' }
    else
      existing_ids = IssueStatus.where(id: closed_ids).pluck(:id).map(&:to_s)
      missing = closed_ids.map(&:to_s) - existing_ids
      if missing.any?
        warnings << { type: :error, message: "Некоторые выбранные статусы удалены (ID: #{missing.join(', ')})" }
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

    # Прогресс = E_closed / E_total × 100%
    progress = e_total > 0 ? (e_closed / e_total) * 100 : 0

    # Освоение = F / B × 100%
    spent = (f / budget) * 100

    # CPI/EAC/Variance не вычисляются без фактических трудозатрат
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

    # Отклонение% = (B - EAC) / B × 100%
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
    return 'Нет данных для расчёта' if metrics[:incomplete] && %i[cpi eac variance].include?(metric_name)

    raw = metrics[:raw]
    case metric_name
    when :progress
      "Прогресс (% выполнения работы)\n" \
      "════════════════════════════════\n" \
      "Формула: E_closed / E_total × 100%\n" \
      "════════════════════════════════\n" \
      "E_total (сумма оценок): #{format_metric_hours(raw[:e_total])} ч\n" \
      "E_closed (закрытые): #{format_metric_hours(raw[:e_closed])} ч\n" \
      "════════════════════════════════\n" \
      "Расчёт: #{format_metric_hours(raw[:e_closed])} / #{format_metric_hours(raw[:e_total])} × 100% = #{format_metric_percent(metrics[:progress])}"
    when :spent
      "Освоение (% расхода бюджета)\n" \
      "════════════════════════════════\n" \
      "Формула: F / B × 100%\n" \
      "════════════════════════════════\n" \
      "F (факт. трудозатраты): #{format_metric_hours(raw[:f])} ч\n" \
      "B (бюджет): #{format_metric_hours(raw[:budget])} ч\n" \
      "════════════════════════════════\n" \
      "Расчёт: #{format_metric_hours(raw[:f])} / #{format_metric_hours(raw[:budget])} × 100% = #{format_metric_percent(metrics[:spent])}"
    when :cpi
      status = cpi_status(metrics[:cpi])
      "CPI — Эффективность\n" \
      "════════════════════════════════\n" \
      "Формула: E_closed / F\n" \
      "════════════════════════════════\n" \
      "E_closed: #{format_metric_hours(raw[:e_closed])} ч\n" \
      "F (факт): #{format_metric_hours(raw[:f])} ч\n" \
      "════════════════════════════════\n" \
      "Расчёт: #{format_metric_hours(raw[:e_closed])} / #{format_metric_hours(raw[:f])} = #{number_with_precision(metrics[:cpi], precision: 2)}\n" \
      "════════════════════════════════\n" \
      "#{status[:icon]} #{status[:text]}"
    when :eac
      "EAC — Прогноз итоговых затрат\n" \
      "════════════════════════════════\n" \
      "Формула: E_total / CPI\n" \
      "════════════════════════════════\n" \
      "E_total: #{format_metric_hours(raw[:e_total])} ч\n" \
      "CPI: #{number_with_precision(metrics[:cpi], precision: 2)}\n" \
      "════════════════════════════════\n" \
      "Расчёт: #{format_metric_hours(raw[:e_total])} / #{number_with_precision(metrics[:cpi], precision: 2)} = #{format_metric_hours(metrics[:eac])} ч"
    when :variance
      variance = metrics[:variance]
      status = if variance.nil?
                 "Нет данных"
               elsif variance > 0
                 "Профицит: уложимся в бюджет"
               elsif variance < 0
                 "Дефицит: бюджета не хватит"
               else
                 "Точно по бюджету"
               end
      "Variance — Отклонение от бюджета\n" \
      "════════════════════════════════\n" \
      "Формула: B - EAC\n" \
      "════════════════════════════════\n" \
      "B (бюджет): #{format_metric_hours(raw[:budget])} ч\n" \
      "EAC (прогноз): #{format_metric_hours(metrics[:eac])} ч\n" \
      "════════════════════════════════\n" \
      "Расчёт: #{format_metric_hours(raw[:budget])} - #{format_metric_hours(metrics[:eac])} = #{format_metric_hours(metrics[:variance])} ч\n" \
      "(#{format_metric_percent(metrics[:variance_percent])})\n" \
      "════════════════════════════════\n" \
      "#{status}"
    else
      ''
    end
  end

  # CPI status with icon and text
  def cpi_status(cpi)
    return { icon: '⚪', text: 'Нет данных', color: nil } if cpi.nil?

    if cpi >= 1.0
      { icon: '🟢', text: 'Норма — работаем по плану или экономим', color: '#ccffcc' }
    elsif cpi >= 0.9
      { icon: '🟡', text: 'Внимание — небольшой перерасход', color: '#ffffcc' }
    else
      { icon: '🔴', text: 'Проблема — значительный перерасход', color: '#ffcccc' }
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

  # Returns background color for metric based on value thresholds
  def metric_color(metric_name, value, metrics = nil)
    return nil if value.nil?

    case metric_name
    when :progress
      nil
    when :spent
      value > 100 ? '#ffcccc' : nil
    when :cpi
      cpi_status(value)[:color]
    when :eac
      nil
    when :variance
      if value < 0
        '#ffcccc' # red - deficit
      elsif value > 0
        '#ccffcc' # green - surplus
      end
    end
  end
end
