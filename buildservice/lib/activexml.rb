begin
  require 'active_support'
rescue LoadError
  require 'rubygems'
  require_gem 'activesupport'
end

require_dependency 'activexml/config'
require_dependency 'activexml/node'
require_dependency 'activexml/base'
require_dependency 'activexml/transport'

ActiveXML::Base.class_eval do
  include ActiveXML::Config
end
