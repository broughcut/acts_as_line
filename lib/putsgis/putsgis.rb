module PutsGIS

  OPERATORS = [:intersects, :covers, :dwithin, :covered_by]

  module Acts

    module GIS

      def self.included(base)
        base.extend ClassMethods
      end

      module Operations
        def make_world_point(obj)
          geom = ActiveRecord::Base.connection.select_value("SELECT transform(setsrid(st_makepoint('#{obj.lng}','#{obj.lat}'),4269),32661);") if obj.lng
        end
      end

      module Calculations
        def units(i,kind,divide=false)
          case kind
          when :miles
            units = i*1609
            units = i/1609 if divide
          when :km
            units = i*1000
            units = i/1000 if divide
          when :days
            units = (i*24)*(60**2)
            units = ((i/60)/60)/24 if divide
          when :hours
            units = (i*60)*60
            units = (i/60)/60 if divide
          when :minutes
            units = i*60
            units = i/60 if divide
          when :projection
            units = i
          end
          units
        end
      end

      module ClassMethods

        include Operations

        def acts_as_line
          before_validation :draw_line if self.column_names.include?("start_date")
          include PutsGIS::Acts::GIS::InstanceMethods
          extend PutsGIS::Acts::GIS::SingletonMethods
        end
        
        def acts_as_world_point
          include Operations
          before_validation :add_point if self.column_names.include?("lat")
          include PutsGIS::Acts::GIS::InstanceMethods
          extend PutsGIS::Acts::GIS::SingletonMethods
        end

        def acts_as_destination(default_departure)
          cattr_accessor :default_departure
          before_validation :drive_time
          self.default_departure = default_departure
        end

      end

      def draw_line
        self.temporal_geom = ActiveRecord::Base.connection.select_value("SELECT setsrid(st_makeline(st_makepoint(0,extract(epoch from TIMESTAMP WITH TIME ZONE '#{self.start_date.xmlschema}')),st_makepoint(0,extract(epoch from TIMESTAMP WITH TIME ZONE '#{self.end_date.xmlschema}'))),-1) AS geom") if self.start_date
      end

      def add_point
        GEO::Post.new(self) if self.lat.nil?
        if self.lat
          geom = make_world_point(self) 
          self.geom = geom
        end
      end

      def drive_time
        departs = self.class.default_departure
        if self.respond_to?(:postcode) && self.postcode
          map = GEO::Drive.new(self.postcode,departs)
        elsif self.respond_to(:lat) && self.lat
          map = GEO::Drive.new([self.lat, self.lng],departs)
        end
        if map
          self.drivetime = map.duration
          self.drivemiles = map.miles
        end
      end
 
      module SingletonMethods 

        include Calculations

        OPERATORS.each do |method|
          define_method(method) do |*params|
            if params.size > 1
              specified_options = params.last
            else
              specified_options = {}
            end
            default_options = {:outcome => true,
                               :units => :projection_units,
                               :segment => false,
                               :geom_col => :temporal_geom,
                               :geom => false,
                               :fkey => :id,
                               :in => true,
                               :select => :all,
                               :distance => false,
                               :drive => nil,
                               :destination => nil,
                               :subquery => {},
                               :conditions => {}}
            options = default_options.merge specified_options
            specified_options.keys.each {|key|
              default_options.keys.include?(key) || raise(InvalidArgumentException, "#{key} is not a valid option key.")
            }
            gis_query(method,params.first,options)
          end
        end



        def set_geom(kind)

          case kind
          when :geom
            ActiveRecord::Base.connection.execute("
              UPDATE #{self.table_name} SET #{kind.to_s} = transform(setsrid(makepoint(lng, lat),4269),32661);")
          else
            ActiveRecord::Base.connection.execute("
              UPDATE #{self.table_name} SET #{kind.to_s} = setsrid(st_makeline(st_makepoint(0,extract(epoch from start_date)),st_makepoint(0,extract(epoch from end_date))),-1);")
          end
            ActiveRecord::Base.connection.execute("
              CLUSTER idx_#{self.table_name}_#{kind} ON #{self.table_name};")
            ActiveRecord::Base.connection.execute("
              VACUUM ANALYZE #{self.table_name};")
        end 

        def gis_query(function,object,options)
          geom_kind = options[:geom_col].to_s
          function = "ST_#{function.to_s.camelize}"
          table = self.table_name
          fkey = options[:fkey].to_s
          subquery = options[:subquery]
          if options[:select] == :all
            select = "*"
          else
            select = "(#{options[:select].to_s.gsub(/:/){}})"
          end
          if options[:geom]
            object_id = options[:geom].id
            geom_b = options[:geom].class.table_name
          else
            object_id = object.id
          end
          object_table = object.table_name
          sql = []
          if options[:geom]
           if options[:in] == false
              notin = 'NOT IN'
            else
              notin = 'IN'
            end
            sql << "SELECT #{select} FROM #{table} WHERE" 
            if options[:conditions].any?
              options[:conditions].each_pair do |key,value|
                if value.class == Range
                  sql << "(#{key} >= #{value.first} AND #{key} <= #{value.last}) AND"
                elsif value.to_s.split('')[0] =~ /^>|^</
                  sql_value = value
                else
                  sql_value = "= '#{value}'"
                end
                sql << "#{key} #{sql_value} AND" unless value.class == Range
              end
            end
            sql << "#{table}.#{fkey} #{notin}"
            sql << "(SELECT DISTINCT on (#{table}.#{fkey}) #{table}.#{fkey} FROM #{object_table} 
                  INNER JOIN #{table} ON #{table}.#{fkey}=#{object_table}.#{self.to_s.downcase}_#{fkey}
                  WHERE (#{function}(#{object_table}.#{geom_kind},(SELECT #{geom_kind} FROM #{geom_b} WHERE id = #{object_id})) = #{options[:outcome]}))"
            if subquery.any?
              function = "ST_#{subquery[:function].to_s.camelize}"
              case subquery[:geom_kind]
              when :geographic
                geom_col = 'geom'
              else
                geom_col = 'temporal_geom'
              end
              geom = "#{subquery[:geom].class.table_name}"
              id = "#{subquery[:geom].id}"
              select = "SELECT #{geom_col} FROM #{geom} WHERE id = #{id}"
              value = units(subquery[:value],subquery[:units])
              sql << "AND (#{function}(#{table}.#{geom_col},(#{select}),#{value}))"
            end
          else
            the_geom = "SELECT #{geom_kind} FROM #{object_table} WHERE id = #{object_id}"
            if options[:segment]
              point_a = "SELECT ST_line_interpolate_point((#{the_geom}),#{options[:segment].first})"
              point_b = "SELECT ST_line_interpolate_point((#{the_geom}),#{options[:segment].last})"
              select_geom = "SELECT setsrid(st_makeline((#{point_a}),(#{point_b})),-1)"
            else
              select_geom = the_geom
            end
            sql = []
            sql << "SELECT #{select} from #{table_name}"
            distance = nil
            if options[:distance]
              distance = ",#{units(options[:distance],options[:units])}"
            end
            sql << "WHERE (#{function}(#{table_name}.#{geom_kind},(#{select_geom})#{distance}) = #{options[:outcome]})"
          end
          if options[:destination]
            destination = options[:destination].to_s.pluralize
            dest_id = "#{options[:destination]}_id"
            within = "drive#{options[:drive].first}"
            value = options[:drive].last
            sql << "AND #{table_name}.#{dest_id} IN
                    (SELECT (#{table_name}.#{dest_id}) FROM #{destination}
                    INNER JOIN #{table_name} ON #{table_name}.#{dest_id}=#{destination}.remote_id
                    WHERE #{destination}.#{within} <= #{value})"
          end
          if options[:conditions].any? && options[:geom] == false
            options[:conditions].each_pair do |key,value|
              if value.to_s.split('')[0] =~ /^>|^</
                sql_value = value
              else
                sql_value = "= '#{value}'"
              end
              sql << "AND #{key} #{sql_value}"
            end
          end
          if sql.size > 2 && options[:geom] == false
            sql[2] = sql[2].gsub(/AND/,'AND (')
            sql[-1] = sql[-1].gsub(/$/,')')
          end
          if options[:select] != :all
            connection.select_values sql.join(' ')
          else
            find_by_sql sql.join(' ')
          end
        end
      end

      module InstanceMethods

        include Calculations

        query_methods = OPERATORS.map {|x| "#{x}?".to_sym}
        
        query_methods.each do |method|
          define_method method do |object|
            gis_query_tf(method,object,options={:geom_col => :temporal_geom})
          end
        end

        def length(options={})
          options[:units] ||= :projection
          options[:geom_col] = :temporal_geom
          gis_query_sum(:length,nil,options)
        end

        def distance(object,options={:geom_col => :temporal_geom})
          options[:units] ||= :projection
          gis_query_sum(:ST_Distance,object,options)
        end
 
        def gis_query_sum(function,object,options)
          geom_kind = options[:geom_col].to_s
          case function
          when :length
            sql = "SELECT sum(length((SELECT #{geom_kind} FROM #{self.class.table_name} WHERE id = #{self.id})))"
          else
            sql = "SELECT sum((#{function.to_s}((SELECT #{geom_kind} FROM #{self.class.table_name} WHERE id = #{self.id}),(SELECT #{geom_kind} FROM #{object.class.table_name} WHERE id = #{object.id}))))"
          end
          result = units(connection.select_value(sql).to_i,options[:units],:divide => true)
        end

        def gis_query_tf(function,object,options)
          geom_kind = options[:geom_col].to_s
          function = "ST_#{function.to_s.gsub(/\?/){}.camelize}"
          first_geom = "SELECT #{geom_kind} FROM #{self.class.table_name} WHERE id = #{self.id}"
          second_geom = "SELECT #{geom_kind} FROM #{object.class.table_name} WHERE id = #{object.id}" 
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
