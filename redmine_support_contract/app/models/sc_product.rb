# frozen_string_literal: true

class ScProduct < ActiveRecord::Base
  has_many :sc_project_products, dependent: :destroy

  validates :name, presence: true, uniqueness: true, length: { maximum: 255 }

  acts_as_list

  scope :sorted, -> { order(position: :asc) }
end
