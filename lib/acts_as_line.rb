module PutGIS
  module ActsAsLine

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods

      def acts_as_line
        before_validation :draw_line

        def touching(object, options={})
          intersects(object,true,options)
        end

        def asunder(object, options={})
          intersects(object,false,options)
        end

        def intersects(object, boolean, options={})
          sql = []
          sql << "SELECT * from #{self.table_name}"
          sql << "WHERE (ST_Intersects(#{self.table_name}.geom,(SELECT geom FROM #{object.class.table_name} WHERE id = #{object.id})) = #{boolean})"
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
      end
    end

    def draw_line
      self.geom = ActiveRecord::Base.connection.select_value("SELECT setsrid(st_makeline(st_makepoint(0,extract(epoch from DATE('#{self.start_date}'))),st_makepoint(0,extract(epoch from DATE('#{self.end_date}')))),-1) AS geom");
    end

    module InstanceMethods

      def self.include(base)
        base.extend SingletonMethods
      end

      module SingletonMethods
      end

    end

  end
end
