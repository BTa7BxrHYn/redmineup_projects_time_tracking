# frozen_string_literal: true

class ScProjectProduct < ActiveRecord::Base
  belongs_to :project
  belongs_to :sc_product

  validates :expires_on, presence: true
  validates :sc_product_id, uniqueness: { scope: :project_id }

  scope :sorted, -> { joins(:sc_product).order('sc_products.position ASC') }

  def expired?
    return false unless expires_on

    expires_on <= Date.today
  end

  def expiring_soon?
    return false unless expires_on

    !expired? && expires_on <= 7.days.from_now.to_date
  end

  def status_class
    if expired?
      'sc-expired'
    elsif expiring_soon?
      'sc-expiring-soon'
    else
      'sc-active'
    end
  end
end
