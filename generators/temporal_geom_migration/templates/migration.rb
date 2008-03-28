class <%= class_name %> < ActiveRecord::Migration
  def self.up
    execute("ALTER TABLE <%=class_name.underscore%> ADD COLUMN temporal_geom geometry;")
    execute("CREATE INDEX idx_<%=class_name.underscore%>_temporal_geom ON <%=class_name.underscore%> USING GIST (temporal_geom);")
    execute("CLUSTER idx_<%=class_name.underscore%>_temporal_geom ON <%=class_name.underscore%>;")
    execute("VACUUM ANALYZE <%=class_name.underscore%>;")
  end

  def self.down
    execute("ALTER TABLE <%= class_name.underscore %> drop column temporal_geom;")
  end
end
