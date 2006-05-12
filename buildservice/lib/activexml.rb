begin
  require 'active_support'
rescue LoadError
  require 'rubygems'
  require_gem 'activesupport'
end

require 'activexml/config'
require 'activexml/node'
require 'activexml/base'
require 'activexml/transport'

ActiveXML::Base.class_eval do
  include ActiveXML::Config
end
