# frozen_string_literal: true

module ProjectsTimeTrackingHelper
  # Calculates project metrics based on budget and issues data
  #
  # @param budget [Float, nil] project budget in hours (B)
  # @param issues_data [Hash] aggregated issues data:
  #   - :estimated [Float] sum of estimated hours for all issues (E_total)
  #   - :closed_estimated [Float] sum of estimated hours for closed issues (E_closed)
  # @param time_spent [Float] total time spent on project (F - фактические трудозатраты)
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
      { icon: '🟢', text: 'Норма — работаем по плану или экономим', color: '#ccffcc' }
    elsif cpi >= 0.9
      { icon: '🟡', text: 'Внимание — небольшой перерасход', color: '#ffffcc' }
    else
      { icon: '🔴', text: 'Проблема — значительный перерасход', color: '#ffcccc' }
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
