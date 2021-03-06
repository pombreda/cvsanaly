class FileType < ActiveRecord::Base
  self.inheritance_column = nil
  attr_accessible :file_id, :type

  belongs_to :files, :class_name => "FileScm", :foreign_key => :file_id
end
