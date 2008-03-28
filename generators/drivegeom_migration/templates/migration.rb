class <%= class_name %> < ActiveRecord::Migration
  def self.up
    execute("ALTER TABLE <%=class_name.underscore%> ADD COLUMN geom_arrive geometry;")
    execute("ALTER TABLE <%=class_name.underscore%> ADD COLUMN geom_depart geometry;")
    execute("CREATE INDEX idx_<%=class_name.underscore%>_geom ON <%=class_name.underscore%> USING GIST (geom_arrive,geom_depart);")
    execute("CLUSTER idx_<%=class_name.underscore%>_geom ON <%=class_name.underscore%>;")
    execute("VACUUM ANALYZE <%=class_name.underscore%>;")


  end

  def self.down
    execute("ALTER TABLE <%=class_name.underscore%> drop column geom_arrive;")
    execute("ALTER TABLE <%=class_name.underscore%> drop column geom_depart;")

  end
end
