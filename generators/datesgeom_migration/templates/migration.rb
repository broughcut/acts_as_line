class <%= class_name %> < ActiveRecord::Migration
  def self.up
    execute("ALTER TABLE <%=class_name.underscore%> ADD COLUMN geom geometry;")
    execute("CREATE INDEX idx_<%=class_name.underscore%>_geom ON <%=class_name.underscore%> USING GIST (geom);")
    execute("CLUSTER idx_<%=class_name.underscore%>_geom ON <%=class_name.underscore%>;")
    execute("VACUUM ANALYZE <%=class_name.underscore%>;")
  end

  def self.down
    execute("ALTER TABLE <%= class_name.underscore %> drop column geom;")
  end
end
