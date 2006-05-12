#!/usr/bin/ruby -w

$LOAD_PATH << './lib'

require 'activexml'
require 'logger'

AZ_ACCESSKEY = "1FM390V8JAP7Q5K4YKG2"

ActiveXML::Base.config do |conf|
  conf.logger = Logger.new( STDERR )

  conf.setup_transport do |map|
    map.default_server :rest, "webservices.amazon.com"
    map.connect :lookup, "rest:///onca/xml?Service=AWSECommerceService&AWSAccessKeyId=#{AZ_ACCESSKEY}" +
                         "&Operation=ItemLookup&ItemId=:asin"
  end
end


class Lookup < ActiveXML::Base
  default_find_parameter :asin
end


def format_response( lookup_result )
  item = lookup_result.Items.Item
  str = <<-END_STR
  -----------------------------------------------------------------
  ASIN: #{item.ASIN}

  Title: #{item.ItemAttributes.Title}
  Authors: #{item.ItemAttributes.each_Author.join(", ")}
  Manufacturer: #{item.ItemAttributes.Manufacturer}
  -----------------------------------------------------------------
  END_STR
end

def format_error( lookup_result )
  errors = lookup_result.Items.Request.Errors
  str = <<-END_STR
  -----------------------------------------------------------------
  Something went wrong:
  
  END_STR
  errors.each_Error do |err|
    str += <<-END_STR
  Errorcode: #{err.Code}
  Message: #{err.Message}
    
    END_STR
  end
  str += "  -----------------------------------------------------------------"
end

while true
  print "Enter ASIN (ISBN) or q to quit: "
  input = STDIN.readline.chomp
  break if input == "q"
  
  response = Lookup.find(input)
  sleep 1 #safety wait; amazon allows only one request per second
  
  if response.Items.Request.has_element? :Errors
    puts format_error( response )
  else
    puts format_response( response )
  end
end


