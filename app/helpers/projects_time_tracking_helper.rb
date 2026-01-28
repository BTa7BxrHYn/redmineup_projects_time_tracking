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
      .filter_map { |id| Integer(id) rescue nil }
      .reject(&:zero?)
  end

  # Returns sanitized budget custom field ID
  def ptt_budget_custom_field_id
    @ptt_budget_custom_field_id ||= begin
      cf_id = ptt_settings['budget_custom_field_id']
      cf_id.present? ? (Integer(cf_id) rescue nil) : nil
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

    # Прогресс = E_closed / E_total × 100%
    progress = e_total > 0 ? (e_closed / e_total) * 100 : 0

    # Освоение = F / B × 100%
    spent = (f / budget) * 100

    # CPI = E_closed / F
    cpi = f > 0 ? e_closed / f : 0

    # EAC = E_total / CPI (или F / Progress в долях)
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
      raw: {
        budget: budget,
        e_total: e_total,
        e_closed: e_closed,
        f: f
      }
    }
  end

  # Generates tooltip text for a specific metric
  def metric_tooltip(metric_name, metrics)
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
      status = if metrics[:variance] > 0
                 "Профицит: уложимся в бюджет"
               elsif metrics[:variance] < 0
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
    if cpi >= 1.0
      { icon: '[OK]', text: 'Норма — работаем по плану или экономим', color: '#ccffcc' }
    elsif cpi >= 0.9
      { icon: '[!]', text: 'Внимание — небольшой перерасход', color: '#ffffcc' }
    else
      { icon: '[X]', text: 'Проблема — значительный перерасход', color: '#ffcccc' }
    end
  end

  # Formats hours value for display
  def format_metric_hours(value)
    number_with_precision(value, precision: 1, strip_insignificant_zeros: true)
  end

  # Formats percent value for display
  def format_metric_percent(value)
    "#{number_with_precision(value, precision: 1)}%"
  end

  # Returns background color for metric based on value thresholds
  def metric_color(metric_name, value, metrics = nil)
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
