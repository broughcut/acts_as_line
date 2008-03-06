module PutGIS
  module ActsAsLine

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods

      def acts_as_line
        before_validation :draw_line
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
        def find_intersecting
          find(:all)
        end
      end

    end

  end
end
