require 'rubygems'
require 'eventmachine'
  
module PutsGIS
  module GEO
    class Call
    
      attr_accessor :response, :page
    
      def initialize(param1=nil,param2=nil,specified_options={})
        
        yapikey = File.readlines("#{GEOPOST_ROOT}/yapikey")[0].gsub(/\n/){}
        default_options = {:server => 'local.yahooapis.com',
                           :preamble => "/MapsService/V1/geocode?appid=#{yapikey}",
                           :kind => :postcode,
                           :page => nil}
        options = default_options.merge specified_options
        specified_options.keys.each do |key|
          default_options.keys.include?(key) || raise(Chronic::InvalidArgumentException, "#{key} is not a valid option key.")
        end
  
        case options[:kind]
        when :postcode
          @page = "#{options[:preamble]}/&zip=#{param1.to_s}"
        when :address
          @page = "#{options[:preamble]}/&location=#{param1.to_s}"
        when :drive
          @page = options[:page]
        end
        @page
        EM.run do
          http = EM::P::HttpClient2.connect options[:server], 80
          d = http.get @page
          d.callback {		
            @response = d.content
            status = d.status
            EM.stop
          }
        end
      end
    end
  end
end
