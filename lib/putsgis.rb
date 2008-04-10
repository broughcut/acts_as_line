GEOPOST_ROOT = File.dirname(__FILE__)
GEOCODED_ROOT = "/home/nonstop/geocoded"
DRIVETIME_ROOT = "/home/nonstop/drivetime"

$LOAD_PATH << File.expand_path(File.dirname(__FILE__))

require 'putsgis/putsgis'
require 'putsgis/geopost'
require 'putsgis/geoaddress'
require 'putsgis/geocall'
require 'putsgis/drive'
