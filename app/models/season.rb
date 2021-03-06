# == Schema Information
#
# Table name: seasons
#
#  id         :integer          not null, primary key
#  name       :string           not null
#  slug       :string           not null
#  created_at :datetime
#  updated_at :datetime
#
# Indexes
#
#  index_seasons_on_slug  (slug) UNIQUE
#

class Season < ActiveRecord::Base
  has_many :works
end
