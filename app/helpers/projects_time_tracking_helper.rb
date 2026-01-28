# frozen_string_literal: true

module ProjectsTimeTrackingHelper
  # Calculates project metrics based on budget, issues data and time spent
  #
  # @param budget [Float, nil] project budget in hours (B)
  # @param issues_data [Hash] aggregated issues data:
  #   - :estimated [Float] sum of estimated hours for all issues (E_total)
  #   - :closed_estimated [Float] sum of estimated hours for closed issues (E_closed)
  #   - :unestimated_count [Integer] count of issues without estimates (N_unest)
  #   - :closed_unestimated_count [Integer] count of closed issues without estimates (N_unest_closed)
  # @param time_spent [Float] total time spent on project (T_spent)
  # @return [Hash, nil] metrics hash or nil if budget is invalid
  def project_metrics(budget, issues_data, time_spent)
    return nil if budget.nil? || budget <= 0

    e_total = issues_data[:estimated] || 0
    e_closed = issues_data[:closed_estimated] || 0
    n_unest = issues_data[:unestimated_count] || 0
    n_unest_closed = issues_data[:closed_unestimated_count] || 0
    t_spent = time_spent || 0

    # Step 1: Implied estimate for unestimated issues
    # E_implied = (B - E_total) / N_unest, if B > E_total and N_unest > 0
    e_implied = if budget > e_total && n_unest > 0
                  (budget - e_total) / n_unest
                else
                  0
                end

    # Step 2: Effective sums
    e_effective = e_total + (n_unest * e_implied)
    e_closed_effective = e_closed + (n_unest_closed * e_implied)

    # Step 3: Main metrics
    # Progress = (E_closed_effective / E_effective) × 100%
    progress = e_effective > 0 ? (e_closed_effective / e_effective) * 100 : 0

    # Spent = (T_spent / B) × 100%
    spent = (t_spent / budget) * 100

    # Efficiency = Progress / Spent
    efficiency = spent > 0 ? progress / spent : 0

    # Step 4: Forecast
    # EAC = T_spent × (E_effective / E_closed_effective)
    eac = e_closed_effective > 0 ? t_spent * (e_effective / e_closed_effective) : 0

    # Variance = B - EAC
    variance = budget - eac

    {
      progress: progress,
      spent: spent,
      efficiency: efficiency,
      eac: eac,
      variance: variance,
      raw: {
        budget: budget,
        e_total: e_total,
        e_closed: e_closed,
        n_unest: n_unest,
        n_unest_closed: n_unest_closed,
        t_spent: t_spent,
        e_implied: e_implied,
        e_effective: e_effective,
        e_closed_effective: e_closed_effective
      }
    }
  end

  # Generates tooltip text for a specific metric
  #
  # @param metric_name [Symbol] :progress, :spent, :efficiency, :eac, :variance
  # @param metrics [Hash] metrics hash from project_metrics
  # @return [String] formatted tooltip text
  def metric_tooltip(metric_name, metrics)
    raw = metrics[:raw]
    case metric_name
    when :progress
      "Прогресс (% выполненной работы)\n" \
      "════════════════════════════════\n" \
      "Формула: (E_closed_eff / E_effective) × 100%\n" \
      "════════════════════════════════\n" \
      "E_total (сумма оценок): #{format_metric_hours(raw[:e_total])} ч\n" \
      "E_closed (закрытые): #{format_metric_hours(raw[:e_closed])} ч\n" \
      "N_unest (без оценки): #{raw[:n_unest]} шт\n" \
      "N_unest_closed (закр. без оценки): #{raw[:n_unest_closed]} шт\n" \
      "E_implied (подразум. оценка): #{format_metric_hours(raw[:e_implied])} ч\n" \
      "════════════════════════════════\n" \
      "E_effective = #{format_metric_hours(raw[:e_total])} + (#{raw[:n_unest]} × #{format_metric_hours(raw[:e_implied])}) = #{format_metric_hours(raw[:e_effective])} ч\n" \
      "E_closed_eff = #{format_metric_hours(raw[:e_closed])} + (#{raw[:n_unest_closed]} × #{format_metric_hours(raw[:e_implied])}) = #{format_metric_hours(raw[:e_closed_effective])} ч\n" \
      "════════════════════════════════\n" \
      "Расчёт: (#{format_metric_hours(raw[:e_closed_effective])} / #{format_metric_hours(raw[:e_effective])}) × 100% = #{format_metric_percent(metrics[:progress])}"
    when :spent
      "Освоение бюджета (% потраченного)\n" \
      "════════════════════════════════\n" \
      "Формула: (T_spent / B) × 100%\n" \
      "════════════════════════════════\n" \
      "T_spent (списано): #{format_metric_hours(raw[:t_spent])} ч\n" \
      "B (бюджет): #{format_metric_hours(raw[:budget])} ч\n" \
      "════════════════════════════════\n" \
      "Расчёт: (#{format_metric_hours(raw[:t_spent])} / #{format_metric_hours(raw[:budget])}) × 100% = #{format_metric_percent(metrics[:spent])}"
    when :efficiency
      eff_status = if metrics[:efficiency] > 1.0
                     "> 1.0 — делаем больше, чем тратим ✓"
                   elsif metrics[:efficiency] == 1.0
                     "= 1.0 — по плану"
                   else
                     "< 1.0 — тратим больше, чем делаем ✗"
                   end
      "Эффективность (темп выполнения)\n" \
      "════════════════════════════════\n" \
      "Формула: Progress / Spent\n" \
      "════════════════════════════════\n" \
      "Progress: #{format_metric_percent(metrics[:progress])}\n" \
      "Spent: #{format_metric_percent(metrics[:spent])}\n" \
      "════════════════════════════════\n" \
      "Расчёт: #{format_metric_percent(metrics[:progress])} / #{format_metric_percent(metrics[:spent])} = #{number_with_precision(metrics[:efficiency], precision: 2)}\n" \
      "════════════════════════════════\n" \
      "#{eff_status}"
    when :eac
      "EAC — Прогноз затрат при завершении\n" \
      "════════════════════════════════\n" \
      "Формула: T_spent × (E_effective / E_closed_eff)\n" \
      "════════════════════════════════\n" \
      "T_spent: #{format_metric_hours(raw[:t_spent])} ч\n" \
      "E_effective: #{format_metric_hours(raw[:e_effective])} ч\n" \
      "E_closed_eff: #{format_metric_hours(raw[:e_closed_effective])} ч\n" \
      "════════════════════════════════\n" \
      "Расчёт: #{format_metric_hours(raw[:t_spent])} × (#{format_metric_hours(raw[:e_effective])} / #{format_metric_hours(raw[:e_closed_effective])}) = #{format_metric_hours(metrics[:eac])} ч"
    when :variance
      var_status = if metrics[:variance] > 0
                     "Экономия: +#{format_metric_hours(metrics[:variance])} ч ✓"
                   elsif metrics[:variance] < 0
                     "Перерасход: #{format_metric_hours(metrics[:variance])} ч ✗"
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
      "════════════════════════════════\n" \
      "#{var_status}"
    else
      ''
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
  def metric_color(metric_name, value)
    case metric_name
    when :progress
      nil # no color for progress
    when :spent
      value > 100 ? '#ffcccc' : nil
    when :efficiency
      if value < 0.8
        '#ffcccc' # red - bad
      elsif value > 1.2
        '#ccffcc' # green - good
      end
    when :eac
      nil # color handled by variance
    when :variance
      if value < 0
        '#ffcccc' # red - over budget
      elsif value > 0
        '#ccffcc' # green - under budget
      end
    end
  end
end
