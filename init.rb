require 'acts_as_line'

ActiveRecord::Base.send(:include, PutsGIS::Acts::Line)
