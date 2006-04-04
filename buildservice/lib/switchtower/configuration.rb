### all of those settings can be overridden in the application specific switchtower config
### files located at <application>/config/deploy.rb

if ENV.has_key? 'BS_SVN_USER'
  set :svnuser, ENV['BS_SVN_USER']
else
  set :svnuser, ENV['USER']
end

set :repository, proc {"--username #{svnuser} https://forgesvn1.novell.com/svn/opensuse/trunk/buildservice/src/#{application}"}

### changelog/branch settings

# sender address of the changelog mail
set :cl_mail_from, "deploy-noreply@opensuse.org"

# recipients of the changelog mail (string or array of strings)
#set :cl_mail_to, ["abauer@suse.de", "cschum@suse.de", "freitag@suse.de", "cwh@suse.de"]
set :cl_mail_to, "opensuse-commit@opensuse.org"

# target url for the branch
set :cl_branch_url, proc {"https://forgesvn1.novell.com/svn/opensuse/branches/deploy/#{application}/#{File.basename release_path}"}

### roles

role :web, "buildserviceapi.suse.de"
role :app, "buildserviceapi.suse.de"
role :db,  "buildserviceapi.suse.de"

### remote settings

# deploy target directory
set :deploy_to, proc {"/srv/www/opensuse/#{application}"}
set :stage_deploy_to, proc {"/srv/www/opensuse_stage/#{application}"}

# user for ssh operations
set :user, "opensuse"


