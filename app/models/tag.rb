class Tag < ActiveRecord::Base
  attr_accessible :name

  has_many :tag_revisions
end
