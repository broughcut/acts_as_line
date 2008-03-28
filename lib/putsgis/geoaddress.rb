require 'putsgis/geocall'
require 'rubygems'
require 'hpricot'

module PutsGIS
  module GEO 
    class Address
  
      attr_accessor :addresses, :address, :country, :lat, :lng
    
      def initialize(obj, country=:GB)
    
        @lng = nil
        @lng = nil

        @country = country.to_s.upcase
        if obj.respond_to?(:address)
          check_cache(obj.address)
          if @lng.nil?
            validate(obj.address.to_s)
            geocode(@address) if @address
          end
          obj.lat = @lat
          obj.lng = @lng
        return obj
         else
           check_cache(obj)
           if @lng.nil?
             validate(obj.to_s)
             geocode(@address) if @address
           end
        end

      end
    
      private
   
      def check_cache(address)
        @addresses = {}
        eval File.readlines("#{GEOCODED_ROOT}/addresses.txt").to_s
        result = @addresses[address]
         if result
           @lng = result[:lng]
           @lat = result[:lat]
         end
      end

      def validate(address)
        case @country.to_sym
        when :GB
          @address = address.gsub(/\s{1,}/,'+').gsub(/'/){} << "+#{@country.to_s}"
        end
      end
    
      def geocode(address)
        response = Call.new(address, :kind => :address).response
        parse(response) unless response.include?("unable to parse")
      end
    
      def parse(response)
        #codes = response.match(/nt\((.*)\),/)[1].split(', ')
        doc = Hpricot.XML(response)
        @lng = doc.at(:Longitude).inner_text.to_f
        @lat = doc.at(:Latitude).inner_text.to_f
        if @addresses[address].nil?
          file = File.open("#{GEOCODED_ROOT}/addresses.txt","a")
          file.puts "addresses['#{address}'] = {:lat => #{@lat}, :lng => #{@lng}}"
          file.close
        end
      end
    end
  end
end
