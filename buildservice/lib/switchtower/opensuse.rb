
desc <<-DESC
Rewritten update_code using svn on deploy machine, not server
DESC
task :update_code, :roles => [:app, :db, :web] do
  on_rollback { delete release_path, :recursive => true }

  require 'tmpdir'
  
  svntmpdir = "#{Dir.tmpdir}/switchtower-svn-tmp-#{$$}"
  tarfile_local = "#{application}.tar.gz"
  tarfile_remote = "#{deploy_to}/#{tarfile_local}"
  scptarget = "#{user}@buildserviceapi:#{tarfile_remote}"
  
  system <<-CMD
    rm -rf #{svntmpdir}
    mkdir -v #{svntmpdir}
    cd #{svntmpdir}
    echo "Checking out from #{repository}..."
    svn co -q #{repository} #{svntmpdir}
    echo "Tarring archive at #{svntmpdir}"
    cd #{application}
    tar zcf ../#{tarfile_local} *
    scp ../#{tarfile_local} #{scptarget}
  CMD

  run <<-CMD
    mkdir -v #{release_path} &&
    tar -z -x -f #{tarfile_remote} -C #{release_path} &&
    rm -vf #{tarfile_remote} &&
    rm -rf #{release_path}/log #{release_path}/public/system &&
    ln -nfs #{shared_path}/log #{release_path}/log &&
    ln -nfs #{shared_path}/system #{release_path}/public/system
  CMD

  system <<-END
    echo "Removing #{svntmpdir}"
    rm -rf #{svntmpdir}
  END
end
