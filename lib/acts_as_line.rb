module PutsGIS
  module Acts
    module Line

      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        def acts_as_line
          before_validation :draw_line if self.column_names.include?("start_date")
          include PutsGIS::Acts::Line::InstanceMethods
          extend PutsGIS::Acts::Line::SingletonMethods
        end
      end

      def draw_line
        self.geom = ActiveRecord::Base.connection.select_value("SELECT setsrid(st_makeline(st_makepoint(0,extract(epoch from DATE('#{self.start_date}'))),st_makepoint(0,extract(epoch from DATE('#{self.end_date}')))),-1) AS geom")
      end
 
      module SingletonMethods
        def intersects(object, options={})
          gis_query(:ST_Intersects,object,true,nil,options)
        end

        def covers(object, options={})
          gis_query(:ST_Covers,object,true,nil,options)
        end

        def covered_by(object, options={})
          gis_query(:ST_CoveredBy,object,true,nil,options)
        end

        def within(object, kind, i, options={})
          secs = secs(kind,i)
          gis_query(:ST_DWithin,object,true,secs,options)
        end

        def secs(kind,i)
          case kind
          when :days
            secs = (i*24)*(60**2)
          when :hours
            secs = (i*60)*60
          when :secs
            secs = i
          end
          secs
        end

        def intersects_segment(object, segment, options={})
          gis_query(:ST_Intersects,object,true,segment,options)
        end

        def not_intersecting(object, options={})
          gis_query(:ST_Intersects,object,false,nil,options)
        end

        def not_intersecting_segment(object, segment, options={})
          gis_query(:ST_Intersects,object,false,segment,options)
        end

        def asunder(object0,object1,select=nil,options={})
          not_in_intersects(object0,object1,select,options)
        end

        def gis_query(function,object,boolean,p,options={})
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
          case function
          when :ST_DWithin
            sql << "WHERE (ST_DWithin(#{self.table_name}.geom,(#{select_geom}),#{p}) = #{boolean})"
          else
            sql << "WHERE (#{function.to_s}(#{self.table_name}.geom,(#{select_geom})) = #{boolean})"
          end
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
          gis_calc(:length,nil,time)
        end

        def distance(object,time=:secs)
          gis_calc(:ST_Distance,object,time)
        end

        def intersects(object,options={})
          gis_query(:ST_Intersects,object,true,nil,options)
        end

        def intersects?(object)
          gis_query_tf(:ST_Intersects,object)
        end

        def covers(object,options={})
          gis_query(:ST_Covers,object,true,nil,options)
        end

        def covers?(object)
          gis_query_tf(:ST_Covers,object)
        end

        def covered_by(object,options={})
          gis_query(:ST_CoveredBy,object,true,nil,options)
        end

        def covered_by?(object)
          gis_query_tf(:ST_CoveredBy,object)
        end


        def not_intersecitng(object,options={})
          gis_query(:ST_Intersects,object,false,nil,options)
        end

        def intersecting_segment(object,segment,options={})
          gis_query(:ST_Intersects,object,true,segment,options)
        end

        def not_intersecting_segment(object,segment,options={})
          gis_query(:ST_Intersects,object,false,segment,options)
        end

        def gis_calc(function,object,time=:secs)
          case function
          when :length
            base_sum = "SELECT sum((length((SELECT geom FROM #{self.class.table_name} WHERE id = #{self.id})))/60)"
          when :ST_Distance
            base_sum = "SELECT sum((ST_Distance((SELECT geom FROM #{self.class.table_name} WHERE id = #{self.id}),(SELECT geom FROM #{object.class.table_name} WHERE id = #{object.id})))/60)"
          end
          case time.to_sym
          when :secs
            sql = "SELECT length((SELECT geom FROM #{self.class.table_name} WHERE id = #{self.id}))" if function == :length
            sql = "SELECT ST_Distance((SELECT geom FROM #{self.class.table_name} WHERE id = #{self.id}),(SELECT geom FROM #{object.class.table_name} WHERE id = #{object.id}))" if function == :ST_Distance
          when :minutes
            sql = base_sum
          when :hours
            sql = "#{base_sum}/60"
          when :days
            sql = "#{base_sum}/60/24"
          end
          connection.select_value(sql).to_i
        end

        def gis_query(function,object,boolean,p,options={})
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
          sql << "WHERE (#{function.to_s}(#{object_table}.geom,(#{select_geom})) = #{boolean})"
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

        def gis_query_tf(function,object)
          first_geom = "SELECT geom FROM #{self.class.table_name} WHERE id = #{self.id}"
          second_geom = "SELECT geom FROM #{object.class.table_name} WHERE id = #{object.id}" 
          sql = "SELECT #{function.to_s}((#{first_geom}),(#{second_geom}))"
          value = connection.select_value sql
          case value
          when "f"
            false
          when "t"
            true
          end
        end
 
      end

    end
  end
end
