#!/usr/bin/ruby
require 'rubygems'
require 'logger'
require 'benchmark'
require 'ping'
require 'open3'
require 'Getopt/Declare'

include Getopt

#============================= OPTIONS ==============================#
# == Options for local machine.
SSH_APP       = 'ssh'
RSYNC_APP     = 'rsync'

options = Getopt::Declare.new(<<EOF)
  -e <file>     file of exclusions  [optional]
  -r <rdir>     remote directory to backup [required]
  -b <bdir>     local backup directory repository [required]
  -l <file>     log file location [optional]
  -a <age>      age of the backups to keep around [required]
  -t <host>     remote host to pull backup from [required]
  -u <user>     remote host user that we log in as [required]
  -p <port>     port for ssh  [optional]
EOF
  
exclude_file  = '~/.rsyncignore' unless options["-e"]
remote_dir = options["-r"]
log_file      = options["-l"]
log_age       = 'daily'

EMPTY_DIR     = '/tmp/empty_rsync_dir/' #NEEDS TRAILING SLASH. TODO: replace this with a tmp dir made randomly each time
# == Options for the remote machine.
remote_backup_target    = options["-t"]
remote_user             = options["-u"]
ssh_port                = '' unless options["-p"]
backup_dir              = options["-b"] + '/' + Time.now.strftime('%Y%m%d')

RSYNC_VERBOSE           = '-v'
RSYNC_OPTS = "--force --ignore-errors --delete-excluded --exclude-from=#{exclude_file} --delete --backup --backup-dir=#{backup_dir} -a --bwlimit=200"

# == Options to control output
DEBUG         = true #If true output to screen else output is sent to log file.
SILENT        = false #Total silent = no log or screen output.
#========================== END OF OPTIONS ==========================#

if DEBUG && !SILENT
  logger = Logger.new(STDOUT, log_age)
elsif log_file != '' && !SILENT
  logger = Logger.new(log_file, log_age)
else
  logger = Logger.new(nil)
end
ssh_port = ssh_port.empty? ? '' : "-e 'ssh -p #{ssh_port}'"
rsync_cleanout_cmd = "#{RSYNC_APP} #{RSYNC_VERBOSE} #{ssh_port} --delete -a #{EMPTY_DIR} #{remote_user}@#{remote_backup_target}:#{backup_dir}"
rsync_cmd = "#{RSYNC_APP} #{RSYNC_VERBOSE} #{ssh_port} #{RSYNC_OPTS} #{remote_dir} #{remote_user}@#{remote_backup_target}:#{backup_dir}/current"

logger.info("Started running at: #{Time.now}")
run_time = Benchmark.realtime do
  begin
    raise Exception, "Unable to find remote host (#{remote_backup_target})" unless Ping.pingecho(remote_backup_target)
       
    Dir.mkdir("#{EMPTY_DIR}")
    logger.debug(rsync_cleanout_cmd)
    logger.debug(rsync_cmd)
#    Open3::popen3("#{rsync_cleanout_cmd}") { |stdin, stdout, stderr|
#      tmp_stdout = stdout.read.strip
#      tmp_stderr = stderr.read.strip
#      logger.info("#{rsync_cleanout_cmd}\n#{tmp_stdout}") unless tmp_stdout.empty?
#      logger.error("#{rsync_cleanout_cmd}\n#{tmp_stderr}") unless tmp_stderr.empty?
#    }
#    Open3::popen3("#{rsync_cmd}") { |stdin, stdout, stderr|
#      tmp_stdout = stdout.read.strip
#      tmp_stderr = stderr.read.strip
#      logger.info("#{rsync_cmd}\n#{tmp_stdout}") unless tmp_stdout.empty?
#      logger.error("#{rsync_cmd}\n#{tmp_stderr}") unless tmp_stderr.empty?
#    }
    FileUtils.rmdir("#{EMPTY_DIR}")
  rescue Errno::EACCES, Errno::ENOENT, Errno::ENOTEMPTY, Exception => e
    logger.fatal(e.to_s)
  end
end
logger.info("Finished running at: #{Time.now} - Execution time: #{run_time.to_s[0, 5]}")
