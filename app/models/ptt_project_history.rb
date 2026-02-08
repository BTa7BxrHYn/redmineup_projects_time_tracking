# frozen_string_literal: true

class PttProjectHistory < ActiveRecord::Base
  self.table_name = 'ptt_project_histories'

  ALLOWED_FIELDS = %w[budget start_date end_date comment].freeze

  # Fields that trigger yellow highlighting in the project list
  HIGHLIGHTABLE_FIELDS = %w[budget start_date end_date].freeze

  FIELD_LABELS = {
    'start_date' => 'Начало проекта',
    'end_date' => 'Окончание проекта',
    'budget' => 'Бюджет проекта',
    'comment' => 'Комментарий'
  }.freeze

  belongs_to :project
  belongs_to :user, optional: true

  validates :project, :field_name, presence: true
  validates :field_name, inclusion: { in: ALLOWED_FIELDS }
  validate :at_least_one_value_present

  scope :sorted, -> { order(created_at: :desc) }

  def field_label
    FIELD_LABELS[field_name] || field_name
  end

  def format_value(value)
    return '(не задано)' if value.blank?

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
      value.to_s
    else
      value
    end
  end

  def formatted_old_value
    format_value(old_value)
  end

  def formatted_new_value
    format_value(new_value)
  end

  # Record changes for a project
  def self.record_changes(project, user, changes)
    changes.each do |field_name, (old_val, new_val)|
      create!(
        project: project,
        user: user,
        field_name: field_name,
        old_value: old_val.to_s.presence,
        new_value: new_val.to_s.presence,
        created_at: Time.current
      )
    end
  end

  private

  def at_least_one_value_present
    return if old_value.present? || new_value.present?

    errors.add(:base, 'At least one of old_value or new_value must be present')
  end
end
