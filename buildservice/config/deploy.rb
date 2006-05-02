# load default opensuse configuration
load '../common/lib/switchtower/configuration.rb'

set :application, "common"

# use common opensuse tasks
load '../common/lib/switchtower/opensuse.rb'
