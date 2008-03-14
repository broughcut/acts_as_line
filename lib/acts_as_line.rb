module PutGIS
  module Acts
    module Line

      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        def acts_as_line
          before_validation :draw_line if self.column_names.include?("start_date")
          include PutGIS::Acts::Line::InstanceMethods
          extend PutGIS::Acts::Line::SingletonMethods
        end
      end

      def draw_line
        self.geom = ActiveRecord::Base.connection.select_value("SELECT setsrid(st_makeline(st_makepoint(0,extract(epoch from DATE('#{self.start_date}'))),st_makepoint(0,extract(epoch from DATE('#{self.end_date}')))),-1) AS geom")
      end
 
      module SingletonMethods
        def touching(object, options={})
          intersects(object,'true',nil,options)
        end

        def touching_segment(object, segment, options={})
          intersects(object,'true',segment,options)
        end

        def not_touching(object, options={})
          intersects(object,'false',nil,options)
        end

        def not_touching_segment(object, segment, options={})
          intersects(object,'false',segment,options)
        end

        def asunder(object0,object1,select=nil,options={})
          not_in_intersects(object0,object1,select,options)
        end

        def intersects(object,boolean,p,options={})
          if object.class == Class
            object_table = object.table_name
          else
            object_table = object.class.table_name
          end
          table = self.table_name
          the_geom = "SELECT geom FROM #{object_table} WHERE id = #{object.id}"
          if p
            point_a = "SELECT ST_line_interpolate_point((#{the_geom}),#{p[0]})"
            point_b = "SELECT ST_line_interpolate_point((#{the_geom}),#{p[1]})"
            select_geom = "SELECT setsrid(st_makeline((#{point_a}),(#{point_b})),-1)"
          else
            select_geom = the_geom
          end
          sql = []
          sql << "SELECT * from #{table}"
          sql << "WHERE (ST_Intersects(#{self.table_name}.geom,(#{select_geom})) = #{boolean})"
          if options.size > 0
            options.each_pair do |key,value|
              if value.to_s.split('')[0] =~ /^>|^</
                sql_value = value
              else
                sql_value = "= '#{value}'"
              end
              sql << "AND #{key} #{sql_value}"
            end
          end
          if sql.size > 2
            sql[2] = sql[2].gsub(/AND/,'AND (')
            sql[-1] = sql[-1].gsub(/$/,')')
          end
          find_by_sql sql.join(' ')
        end

        def not_in_intersects(object0, object1, select, options)
          table = self.table_name
          object0 = object0.table_name
          object = object1.class.table_name
          sql = []
          if select
            sql << "SELECT (#{select.to_s}) FROM #{table} WHERE #{table}.id NOT IN"
          else
            sql << "SELECT * FROM #{table} WHERE #{table}.id NOT IN"
          end 
            sql << "(SELECT DISTINCT on (#{table}.id) #{table}.id FROM #{object0} 
                  INNER JOIN #{table} ON #{table}.id=#{object0}.#{self.to_s.downcase}_id
                  WHERE (ST_Intersects(#{object0}.geom,(SELECT geom FROM #{object} WHERE id = #{object1.id})) = true))"
          if options.size > 0
            options.each_pair do |key,value|
             if value.to_s.split('')[0] =~ /^>|^</
               sql_value = value
             else
               sql_value = "= '#{value}'"
              end
              sql << "AND #{key} #{sql_value}"
            end
          end
          if sql.size > 2
            sql[2] = sql[2].gsub(/AND/,'AND (')
            sql[-1] = sql[-1].gsub(/$/,')')
          end
          sql = sql.join(' ')
          if select
            connection.select_all(sql)
          else
            find_by_sql sql
          end
        end

        def set_geom
          ActiveRecord::Base.connection.execute("
            UPDATE #{self.table_name} SET geom = setsrid(st_makeline(st_makepoint(0,extract(epoch from start_date)),st_makepoint(0,extract(epoch from end_date))),-1);")
          ActiveRecord::Base.connection.execute("
            CLUSTER idx_#{self.table_name}_dates_geom ON #{self.table_name};")
          ActiveRecord::Base.connection.execute("
            VACUUM ANALYZE #{self.table_name};")
        end 

      end

      module InstanceMethods
 
        def duration(time=:secs)
          calc_duration(self,time)
        end

        def touching(object,options={})
          intersects(object,'true',nil,options)
        end

        def not_touching(object,options={})
          intersects(object,'false',nil,options)
        end

        def touching_segment(object,segment,options={})
          intersects(object,'true',segment,options)
        end

        def not_touching_segment(object,segment,options={})
          intersects(object,'false',segment,options)
        end
        def calc_duration(object,time=:secs)
          base_sum = "SELECT sum((length((SELECT geom FROM #{object.class.table_name} WHERE id = #{object.id})))/60)"
          case time.to_sym
          when :secs
            sql = "SELECT length((SELECT geom FROM #{object.class.table_name} WHERE id = #{object.id}))"
          when :minutes
            sql = base_sum
          when :hours
            sql = "#{base_sum}/60"
          when :days
            sql = "#{base_sum}/60/24"
          end
          connection.select_value(sql).to_i
        end

        def intersects(object,boolean,p,options={})
          if object.class == Class
            object_find = object
            object_table = object.table_name
          else
            object_find = object_class
            object_table = object.class.table_name
          end
          the_geom = "SELECT geom FROM #{self.class.table_name} WHERE id = #{self.id}"
          if p
            point_a = "SELECT ST_line_interpolate_point((#{the_geom}),#{p[0]})"
            point_b = "SELECT ST_line_interpolate_point((#{the_geom}),#{p[1]})"
            select_geom = "SELECT setsrid(st_makeline((#{point_a}),(#{point_b})),-1)"
          else
            select_geom = the_geom
          end
          sql = []
          sql << "SELECT * from #{object_table}"
          sql << "WHERE (ST_Intersects(#{object_table}.geom,(#{select_geom})) = #{boolean})"
          if options.size > 0
            options.each_pair do |key,value|
              if value.to_s.split('')[0] =~ /^>|^</
                sql_value = value
              else
                sql_value = "= '#{value}'"
              end
              sql << "AND #{key} #{sql_value}"
            end
          end
          if sql.size > 2
            sql[2] = sql[2].gsub(/AND/,'AND (')
            sql[-1] = sql[-1].gsub(/$/,')')
          end
          object_find.find_by_sql sql.join(' ')
        end
      end

    end
  end
end
