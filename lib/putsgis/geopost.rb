require 'putsgis/geocall'
require 'rubygems'
require 'hpricot'

module PutsGIS
  module GEO 
    class Post
  
      attr_accessor :postcode, :lat, :lng, :partial, :part, :country, :valid
    
      def initialize(obj, country=:GB)
    
        @part = nil
        @country = country.to_s.upcase
        @valid = false
        @lat = nil
        @lng = nil
        
        if obj.respond_to?(:postcode)
          validate(obj.postcode.to_s)
          geocode(@postcode) if @postcode
          obj.lat = @lat
          obj.lng = @lng
          return obj
        else
          validate(obj.to_s)
          geocode(@postcode) if @postcode
        end
      end
    
      private
    
      def validate(code)
        case @country.to_sym
        when :GB
          code.gsub!(/\s|\W/){}
          code.upcase!
          @part = code.split('+').first
          if code.size > 4
            @postcode = code.split('').insert(-4,'+').join('')
          else
            @postcode = (code.split('')[0..3]).join('')
          end
          @valid = true if @postcode.gsub(/\+/,' ').match(/GIR 0AA|[A-PR-UWYZ]([0-9]{1,2}|([A-HK-Y][0-9]|[A-HK-Y][0-9]([0-9]|[ABEHMNPRV-Y]))|[0-9][A-HJKS-UW]) [0-9][ABD-HJLNP-UW-Z]{2}/)
        when :US
          @postcode = code.to_s.gsub(/[aA-zZ]|\W|\s/){}
          if @postcode.size == 9
            @postcode = @postcode.split('').insert(5,'-').join('')
            @part = @postcode.split('')[0..4].join('')
          end
          @valid = true if @postcode.match(/(^\d{5}$)|(^\d{5}-\d{4}$)/)
        else
          @postcode = code
        end
      end
    
      def geocode(code)
        codes = {}
        eval File.readlines("#{GEOCODED_ROOT}/#{country.to_s}.txt").to_s
    
        if codes[code]
          @lat = codes[code][:lat]
          @lng = codes[code][:lng]
        elsif @valid
          response = Call.new(code,@country).response
          parse(response) if response.include?('Latitude')
        elsif @lat.nil? && codes[@part]
          @lat = codes[@part][:lat]
          @lng = codes[@part][:lng]
          @partial = true
        elsif @country == "US"
          response = Call.new(@part,@country).response
          parse(response) if response.include?('Zoom')
          @partial = true
        else
          puts "#{code} not found"
          @postcode = nil
        end
        
        code = @part if @partial
        if codes[code].nil? && @lng
          file = File.open("#{GEOCODED_ROOT}/#{country.to_s}.txt", "a")
          file.puts "codes['#{code}'] = {:lat => '#{@lat}', :lng => '#{@lng}'}"
          file.close
        end
      end
    
    
      def parse(response,partial=false)
        #codes = response.match(/nt\((.*)\),/)[1].split(', ')
        doc = Hpricot.XML(response)
        @lng = doc.at(:Longitude).inner_text.to_f
        @lat = doc.at(:Latitude).inner_text.to_f
        @partial = partial
      end
    end
  end
end
