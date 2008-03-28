require 'putsgis/geocall'
require 'putsgis/geopost'
require 'putsgis/putsgis'
require 'rubygems'
require 'hpricot'

module PutsGIS
  module GEO
    class Drive

      include PutsGIS::Acts::GIS::Operations

      attr_accessor :depart, :arrive, :duration, :miles

      def initialize(code1,code2)
        vectors = {}
        if code1.class == Array
          a = code1.join('+')
        else
          a = Post.new(code1).postcode
        end
        if code2.class == Array
          b = code2.join('+')
        else
          b = Post.new(code2).postcode
        end
        vector = "#{a}>#{b}"
        @depart = a
        @arrive = b
        @miles = nil
        @duration = nil 
        eval File.readlines("#{DRIVETIME_ROOT}/drive.txt").to_s
        if vectors[vector]
          result = vectors[vector]
          @depart = result[:arrive]
          @arrive = result[:depart]
          @duration = result[:duration]
          @miles = result[:miles]
          if @miles == 0.0
            @miles = nil
            @duration = nil
          end
        else
          drive
          @miles = nil if @miles == 0.0
          if @miles
            file = File.open("#{DRIVETIME_ROOT}/drive.txt", "a")
            file.puts "vectors['#{vector}'] = {:miles => #{@miles}, :duration => #{@duration}, :arrive => '#{arrive}', :depart => '#{depart}'}"
            file.close
          end
        end
      end

      def drive
        page = "/maps?f=d&hl=en&geocode=&time=&date=&ttype=&saddr=#{@depart}&daddr=#{@arrive}&output=html"
        response = Call.new(nil,nil,{:kind => :drive, :server => 'maps.google.com', :page => page}).response
        doc = Hpricot(response)
        #@to = (doc/"#ddw_addr_area_0/span").inner_html.gsub(/,.*/,'')
        #@from = (doc/"#ddw_addr_area_1/span").inner_html.gsub(/<.*/,'')
        result = (doc/"td.timedist/div.noprint/div").inner_html
        @miles = result.gsub(/&.*/){}.to_f
        time = result.gsub(/.*11;\s/){}
        if time.include?('hour')
          time = time.gsub(/[aA-zZ]/){}.split(' ').map! {|it| it.to_i}
          @duration = (time.first*60) + time.last
        else
          @duration = time.gsub(/[aA-zZ]/){}.to_i
        end
      end
    end
  end
end
