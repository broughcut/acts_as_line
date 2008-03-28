module PutsGIS
  module GEO

    module InstanceMethods
    end


    module SingletonMethods

     Venue.drive(:miles => 10)

      def drive(specified_options={})
        default_options = {:miles => nil,
                           :duration => :nil}
        options = default_options.merge specified_options
        specified_options.keys.each {|key|
        default_options.keys.include?(key) || raise(InvalidArgumentException, "#{key} is not a valid option key.")
        }
        table = self.table_name
        sql << "SELECT * FROM #{table}" 
        sql << " WHERE #{table}.geom IN"
        sql << "(SELECT DISTINCT on (#{table}.geom) #{table}.geom FROM drives
                 INNER JOIN #{table} ON #{table}.geom=drives.geom_d"
        if options.values.any? && options[:join] == false
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
end
