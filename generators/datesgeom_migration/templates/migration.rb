class <%= class_name %> < ActiveRecord::Migration
  def self.up
    execute("ALTER TABLE <%= class_name.underscore %> ADD COLUMN geom geometry;")
    execute("CREATE INDEX idx_<%= class_name.underscore %>_dates_geom ON <%= class_name.underscore %> USING GIST (geom);")
  end

  def self.down
    execute("ALTER TABLE <%= class_name.underscore %> drop column geom;")
  end
end
