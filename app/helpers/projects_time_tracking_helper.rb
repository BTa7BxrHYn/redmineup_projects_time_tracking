# frozen_string_literal: true

module ProjectsTimeTrackingHelper
  # Calculates project metrics based on budget, issues data and time spent
  #
  # @param project [Project] the project
  # @param budget [Float, nil] project budget in hours
  # @param issues_data [Hash] aggregated issues data:
  #   - :estimated [Float] sum of estimated hours for all issues
  #   - :closed_estimated [Float] sum of estimated hours for closed issues
  #   - :unestimated_count [Integer] count of issues without estimates
  #   - :closed_unestimated_count [Integer] count of closed issues without estimates
  # @param time_spent [Float] total time spent on project
  # @return [Hash, nil] metrics hash or nil if budget is invalid
  def project_metrics(project, budget, issues_data, time_spent)
    return nil if budget.nil? || budget <= 0

    e_total = issues_data[:estimated] || 0
    e_closed = issues_data[:closed_estimated] || 0
    n_unest = issues_data[:unestimated_count] || 0
    n_unest_closed = issues_data[:closed_unestimated_count] || 0
    t_spent = time_spent || 0

    # Step 1: Distribute remainder to unestimated issues
    remainder = [budget - e_total, 0].max
    unest_estimate = n_unest > 0 ? remainder / n_unest : 0

    # Step 2-3: Calculate effective sums
    e_effective = e_total + (n_unest * unest_estimate)
    e_closed_effective = e_closed + (n_unest_closed * unest_estimate)

    # Step 4: Calculate metrics
    progress = e_effective > 0 ? (e_closed_effective / e_effective) * 100 : 0
    budget_used = budget > 0 ? (t_spent / budget) * 100 : 0
    health = budget > 0 ? (e_effective / budget) * 100 : 0
    efficiency = budget_used > 0 ? progress / budget_used : 0

    {
      progress: progress,
      budget_used: budget_used,
      health: health,
      efficiency: efficiency,
      raw: {
        budget: budget,
        e_total: e_total,
        e_closed: e_closed,
        n_unest: n_unest,
        n_unest_closed: n_unest_closed,
        t_spent: t_spent,
        unest_estimate: unest_estimate,
        e_effective: e_effective,
        e_closed_effective: e_closed_effective
      }
    }
  end

  # Generates tooltip text for a specific metric
  #
  # @param metric_name [Symbol] :budget_used, :health, or :efficiency
  # @param metrics [Hash] metrics hash from project_metrics
  # @return [String] formatted tooltip text
  def metric_tooltip(metric_name, metrics)
    raw = metrics[:raw]
    case metric_name
    when :budget_used
      "Освоение бюджета\n" \
      "═══════════════════\n" \
      "Формула: (T_spent / B) × 100%\n" \
      "═══════════════════\n" \
      "T_spent (списано): #{format_metric_hours(raw[:t_spent])}\n" \
      "B (бюджет): #{format_metric_hours(raw[:budget])}\n" \
      "═══════════════════\n" \
      "Расчёт: (#{format_metric_hours(raw[:t_spent])} / #{format_metric_hours(raw[:budget])}) × 100% = #{number_with_precision(metrics[:budget_used], precision: 1)}%"
    when :health
      "Здоровье проекта\n" \
      "═══════════════════\n" \
      "Формула: (E_effective / B) × 100%\n" \
      "═══════════════════\n" \
      "E_total (сумма оценок): #{format_metric_hours(raw[:e_total])}\n" \
      "N_unest (без оценки): #{raw[:n_unest]} шт\n" \
      "Оценка неоценённой: #{format_metric_hours(raw[:unest_estimate])}\n" \
      "E_effective: #{format_metric_hours(raw[:e_total])} + (#{raw[:n_unest]} × #{format_metric_hours(raw[:unest_estimate])}) = #{format_metric_hours(raw[:e_effective])}\n" \
      "B (бюджет): #{format_metric_hours(raw[:budget])}\n" \
      "═══════════════════\n" \
      "Расчёт: (#{format_metric_hours(raw[:e_effective])} / #{format_metric_hours(raw[:budget])}) × 100% = #{number_with_precision(metrics[:health], precision: 1)}%"
    when :efficiency
      "Эффективность\n" \
      "═══════════════════\n" \
      "Формула: Прогресс / Освоение\n" \
      "═══════════════════\n" \
      "Прогресс: #{number_with_precision(metrics[:progress], precision: 1)}%\n" \
      "Освоение: #{number_with_precision(metrics[:budget_used], precision: 1)}%\n" \
      "═══════════════════\n" \
      "Расчёт: #{number_with_precision(metrics[:progress], precision: 1)}% / #{number_with_precision(metrics[:budget_used], precision: 1)}% = #{number_with_precision(metrics[:efficiency], precision: 2)}\n" \
      "═══════════════════\n" \
      "> 1.0 — быстрее плана\n" \
      "= 1.0 — по плану\n" \
      "< 1.0 — медленнее плана"
    else
      ''
    end
  end

  # Formats hours value for display
  #
  # @param value [Float] hours value
  # @return [String] formatted hours string
  def format_metric_hours(value)
    number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
  end

  # Returns background color for metric based on value thresholds
  #
  # @param metric_name [Symbol] :budget_used, :health, or :efficiency
  # @param value [Float] metric value
  # @return [String, nil] CSS color or nil
  def metric_color(metric_name, value)
    case metric_name
    when :budget_used
      value > 100 ? '#ffcccc' : nil
    when :health
      if value > 110
        '#ffcccc'
      elsif value < 90
        '#ffffcc'
      end
    when :efficiency
      if value < 0.8
        '#ffcccc'
      elsif value > 1.2
        '#ccffcc'
      end
    end
  end
end
