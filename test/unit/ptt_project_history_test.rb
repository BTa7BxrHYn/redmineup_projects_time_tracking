# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

class PttProjectHistoryTest < ActiveSupport::TestCase
  fixtures :projects, :users

  def setup
    @project = Project.find(1)
    @user = User.find(2)
  end

  # ── validations ──

  test 'rejects field_name outside the allowed list' do
    h = PttProjectHistory.new(project: @project, field_name: 'unknown', new_value: 'x')
    assert_not h.valid?
    assert_includes h.errors.attribute_names, :field_name
  end

  test 'accepts allowed field names' do
    PttProjectHistory::ALLOWED_FIELDS.each do |field|
      h = PttProjectHistory.new(project: @project, field_name: field, new_value: 'x')
      assert h.valid?, "expected #{field} to be valid"
    end
  end

  test 'requires at least one of old or new value' do
    h = PttProjectHistory.new(project: @project, field_name: 'budget')
    assert_not h.valid?
    assert h.errors[:base].any?
  end

  test 'requires a project' do
    h = PttProjectHistory.new(field_name: 'budget', new_value: '10')
    assert_not h.valid?
  end

  test 'user is optional' do
    h = PttProjectHistory.new(project: @project, user: nil, field_name: 'budget', new_value: '10')
    assert h.valid?
  end

  # ── record_changes ──

  test 'record_changes persists a change row' do
    assert_difference 'PttProjectHistory.count', 1 do
      PttProjectHistory.record_changes(@project, @user, { 'budget' => ['10', '20'] })
    end
    h = PttProjectHistory.where(project_id: @project.id, field_name: 'budget').last
    assert_equal '10', h.old_value
    assert_equal '20', h.new_value
    assert_equal @user.id, h.user_id
  end

  test 'record_changes stores blank values as nil' do
    PttProjectHistory.record_changes(@project, @user, { 'budget' => [nil, '20'] })
    h = PttProjectHistory.where(project_id: @project.id, field_name: 'budget').last
    assert_nil h.old_value
    assert_equal '20', h.new_value
  end

  test 'record_changes writes multiple fields' do
    assert_difference 'PttProjectHistory.count', 2 do
      PttProjectHistory.record_changes(@project, @user, {
        'budget' => ['10', '20'],
        'start_date' => [nil, '2026-01-01']
      })
    end
  end

  # ── format_value ──

  test 'format_value formats dates as dd.mm.yyyy' do
    h = PttProjectHistory.new(field_name: 'start_date')
    assert_equal '02.01.2026', h.format_value('2026-01-02')
  end

  test 'format_value returns raw string for unparseable date' do
    h = PttProjectHistory.new(field_name: 'start_date')
    assert_equal 'not-a-date', h.format_value('not-a-date')
  end

  test 'format_value appends hours suffix to budget' do
    h = PttProjectHistory.new(field_name: 'budget')
    assert_match(/5/, h.format_value('5'))
  end

  test 'format_value returns placeholder for blank' do
    h = PttProjectHistory.new(field_name: 'budget')
    assert h.format_value('').present?
  end
end
