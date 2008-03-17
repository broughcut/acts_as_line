module PutsGIS

  OPERATORS = [:intersects, :covers, :d_within, :covered_by]

  module Acts
    module Line

      def self.included(base)
        base.extend ClassMethods
      end

      module Calculations
        def secs(i,kind)
          case kind
          when :days
            secs = (i*24)*(60**2)
          when :hours
            secs = (i*60)*60
          when :minutes
            secs = i*60
          when :secs
            secs = i
          end
          secs
        end
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

        OPERATORS.each do |method|
          define_method(method) do |*params|
            p params.last
            if params.size > 1
              specified_options = params.last
            else
              specified_options = {}
            end
            default_options = {:outcome => true,
                               :units => :secs,
                               :segment => false,
                               :join => false,
                               :id => false,
                               :included => false,
                               :select => :all,
                               :conditions => {}}
            options = default_options.merge specified_options
            specified_options.keys.each {|key|
              default_options.keys.include?(key) || raise(InvalidArgumentException, "#{key} is not a valid option key.")
            }
            gis_query(method,params.first,options)
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

        def gis_query(function,object,options)
          function = "ST_#{function.to_s.camelize}"
          table = self.table_name
          if options[:join]
            if options[:id].class == Fixnum
              object_id = options[:id]
            else 
              object_id = options[:id].id
            end
            object_table = object.table_name
          else
            object_table = object.class.table_name
            object_id = object.id
          end
          sql = []
          if options[:join]
            if options[:select] == :all
              select = "*"
            else
              select = "(#{options[:select].gsub(/:/){}})"
            end
            if options[:included] == false
              notin = 'NOT IN'
            else
              notin = 'IN'
            end
            sql << "SELECT #{select} FROM #{table} WHERE #{table}.id #{notin}"
            sql << "(SELECT DISTINCT on (#{table}.id) #{table}.id FROM #{object_table} 
                  INNER JOIN #{table} ON #{table}.id=#{object_table}.#{self.to_s.downcase}_id
                  WHERE (#{function}(#{object_table}.geom,(SELECT geom FROM #{options[:join].to_s} WHERE id = #{object_id})) = #{options[:outcome]}))"
          else
            the_geom = "SELECT geom FROM #{object_table} WHERE id = #{object_id}"
            if options[:segment]
              point_a = "SELECT ST_line_interpolate_point((#{the_geom}),#{options[:segment].first})"
              point_b = "SELECT ST_line_interpolate_point((#{the_geom}),#{options[:segment].last})"
              select_geom = "SELECT setsrid(st_makeline((#{point_a}),(#{point_b})),-1)"
            else
              select_geom = the_geom
            end
            sql = []
            sql << "SELECT * from #{table_name}"
            distance = nil
            if options[:distance]
              distance = ",#{calc_units(options[:distance],options[:units])}"
            end
            sql << "WHERE (#{function}(#{table_name}.geom,(#{select_geom})#{distance}) = #{options[:outcome]})"
          end
          if options[:conditions].any?
            options[:conditions].each_pair do |key,value|
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
      end


      module InstanceMethods

        query_methods = OPERATORS.map {|x| "#{x}?".to_sym}
        
        query_methods.each do |method|
          define_method method do |object|
            gis_query_tf(method,object)
          end
        end

        def duration(options={})
          options[:units] ||= :secs
          gis_query_sum(:length,nil,options)
        end

        def distance(object,options={})
          options[:units] ||= :secs
          gis_query_sum(:ST_Distance,object,options)
        end
 
        def gis_query_sum(function,object,options)
          case function
          when :length
            sql = "SELECT sum(length((SELECT geom FROM #{self.class.table_name} WHERE id = #{self.id})))"
          else
            sql = "SELECT sum((#{function.to_s}((SELECT geom FROM #{self.class.table_name} WHERE id = #{self.id}),(SELECT geom FROM #{object.class.table_name} WHERE id = #{object.id}))))"
          end

          result = connection.select_value(sql).to_i
          
          case options[:units].to_sym
          when :secs
            result
          when :minutes
            result/60
          when :hours
            (result/60)/60
          when :days
            ((result/60)/60)/24
          end
        end

        def gis_query_tf(function,object)
          function = "ST_#{function.to_s.gsub(/\?/){}.camelize}"
          first_geom = "SELECT geom FROM #{self.class.table_name} WHERE id = #{self.id}"
          second_geom = "SELECT geom FROM #{object.class.table_name} WHERE id = #{object.id}" 
          sql = "SELECT #{function}((#{first_geom}),(#{second_geom}))"
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
