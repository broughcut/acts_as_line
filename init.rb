require 'putsgis.rb'

ActiveRecord::Base.send(:include, PutsGIS::Acts::GIS)
