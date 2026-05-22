# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

class ProjectMetricsTest < ActiveSupport::TestCase
  include ProjectsTimeTrackingHelper

  def issues(estimated, closed)
    { estimated: estimated, closed_estimated: closed }
  end

  # ── project_metrics: guard conditions ──

  test 'returns nil when budget is nil' do
    assert_nil project_metrics(nil, issues(10, 5), 5)
  end

  test 'returns nil when budget is zero' do
    assert_nil project_metrics(0, issues(10, 5), 5)
  end

  test 'returns nil when budget is negative' do
    assert_nil project_metrics(-10, issues(10, 5), 5)
  end

  test 'marks incomplete when no time spent' do
    m = project_metrics(100, issues(80, 40), 0)
    assert m[:incomplete]
    assert_nil m[:cpi]
    assert_nil m[:eac]
    assert_nil m[:variance]
    # progress/spent are still computed
    assert_in_delta 50.0, m[:progress], 0.001
    assert_in_delta 0.0, m[:spent], 0.001
  end

  test 'marks incomplete when no closed estimates' do
    m = project_metrics(100, issues(80, 0), 50)
    assert m[:incomplete]
    assert_nil m[:cpi]
  end

  # ── project_metrics: README worked example ──
  # B=100, E_total=80, E_closed=40, F=50 → progress 50%, spent 50%, CPI 0.8, EAC 100, Variance 0
  test 'computes the README example correctly' do
    m = project_metrics(100, issues(80, 40), 50)
    refute m[:incomplete]
    assert_in_delta 50.0, m[:progress], 0.001
    assert_in_delta 50.0, m[:spent], 0.001
    assert_in_delta 0.8, m[:cpi], 0.001
    assert_in_delta 100.0, m[:eac], 0.001
    assert_in_delta 0.0, m[:variance], 0.001
    assert_in_delta 0.0, m[:variance_percent], 0.001
  end

  test 'progress is zero when no total estimates' do
    m = project_metrics(100, issues(0, 0), 50)
    assert_in_delta 0.0, m[:progress], 0.001
  end

  # ── metric_css_class ──

  test 'metric_css_class flags overbudget spent' do
    assert_equal 'ptt-overbudget', metric_css_class(:spent, 120)
    assert_nil metric_css_class(:spent, 80)
  end

  test 'metric_css_class maps cpi thresholds' do
    assert_equal 'ptt-good', metric_css_class(:cpi, 1.0)
    assert_equal 'ptt-warning', metric_css_class(:cpi, 0.95)
    assert_equal 'ptt-overbudget', metric_css_class(:cpi, 0.5)
  end

  test 'metric_css_class maps variance sign' do
    assert_equal 'ptt-overbudget', metric_css_class(:variance, -5)
    assert_equal 'ptt-good', metric_css_class(:variance, 5)
    assert_nil metric_css_class(:variance, 0)
  end

  test 'metric_css_class returns nil for nil value' do
    assert_nil metric_css_class(:cpi, nil)
  end

  # ── cpi_status (icons are locale-independent) ──

  test 'cpi_status icon reflects thresholds' do
    assert_equal '⚪', cpi_status(nil)[:icon]
    assert_equal '🟢', cpi_status(1.0)[:icon]
    assert_equal '🟡', cpi_status(0.9)[:icon]
    assert_equal '🔴', cpi_status(0.5)[:icon]
  end
end
