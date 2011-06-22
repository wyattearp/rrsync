#!/usr/bin/ruby
require 'rubygems'
require 'logger'
require 'benchmark'
require 'ping'
require 'open3'
require 'Getopt/Declare'

include Getopt

class Time
  def yesterday
    self - 86400
  end
end

def get_last_backup_dir(backup_path)
  # we're willing to try and go back at most 1 week before we say screw it
  count = 7
  backup_day = Time.now.yesterday
  possible_dir = backup_path + "/" + backup_day.strftime('%Y%m%d')
  while not File.directory?(possible_dir) and count < 7
    backup_day = backup_day.yesterday
    possible_dir = backup_path + "/" + backup_day.strftime('%Y%m%d')
    count = count + 1
  end

  if count == 7
    # we looked 7days back and couldn't find anything, no reason to leave
    # our backup out that far
    backup_day = Time.now.yesterday
    possible_dir = backup_path + "/" + backup_day.strftime('%Y%m%d')
  end
  return possible_dir
end

#============================= OPTIONS ==============================#
# == Options for local machine.
SSH_APP       = 'ssh'
RSYNC_APP     = 'rsync'

options = Getopt::Declare.new(<<EOF)
  -e <file>     file of exclusions  [optional]
  -r <rdir>     remote directory to backup [required]
  -b <bdir>     local backup directory repository [required]
  -l <file>     log file location [optional]
  -a <age>      age in days of the backups to keep around [required]
  -t <host>     remote host to pull backup from [required]
  -u <user>     remote host user that we log in as [required]
  -p <port>     port for ssh  [optional]
  -n            dryrun ... just for testing [optional]
EOF
  
exclude_file  = options["-e"]
remote_dir    = options["-r"]
log_file      = options["-l"]
log_age       = options["-a"]

EMPTY_DIR     = '/tmp/empty_rsync_dir/' #NEEDS TRAILING SLASH. TODO: replace this with a tmp dir made randomly each time
# == Options for the remote machine.
remote_backup_target    = options["-t"]
remote_user             = options["-u"]
ssh_port                = '' unless options["-p"]
# determine the previous backup directory
link_dir                = get_last_backup_dir(options["-b"])
backup_dir              = options["-b"] + "/" + Time.now.strftime('%Y%m%d')


RSYNC_VERBOSE           = '-v'
RSYNC_OPTS = "--force --ignore-errors --delete-excluded --exclude-from=#{exclude_file} --delete --backup --bwlimit=200 -a -p -t --numeric-ids --link-dest=#{link_dir} #{options["-n"]}"
   


logger = Logger.new(STDOUT, log_age)

ssh_port = ssh_port.empty? ? '' : "-e 'ssh -p #{ssh_port}'"
rsync_cleanout_cmd = "#{RSYNC_APP} #{RSYNC_VERBOSE} #{ssh_port} --delete -a #{EMPTY_DIR} #{backup_dir}"
rsync_cmd = "#{RSYNC_APP} #{RSYNC_VERBOSE} #{ssh_port} #{RSYNC_OPTS} #{remote_user}@#{remote_backup_target}:#{remote_dir} #{backup_dir}"

logger.info("Started running at: #{Time.now}")
run_time = Benchmark.realtime do
  begin
    raise Exception, "Unable to find remote host (#{remote_backup_target})" unless Ping.pingecho(remote_backup_target)
       
    Dir.mkdir("#{EMPTY_DIR}")
#    Open3::popen3("#{rsync_cleanout_cmd}") { |stdin, stdout, stderr|
#      tmp_stdout = stdout.read.strip
#      tmp_stderr = stderr.read.strip
#      logger.info("#{rsync_cleanout_cmd}\n#{tmp_stdout}") unless tmp_stdout.empty?
#      logger.error("#{rsync_cleanout_cmd}\n#{tmp_stderr}") unless tmp_stderr.empty?
#    }
    Dir.mkdir(backup_dir) unless File.directory?(backup_dir) 
    puts rsync_cmd
    Open3::popen3("#{rsync_cmd}") { |stdin, stdout, stderr|
      tmp_stdout = stdout.read.strip
      tmp_stderr = stderr.read.strip
      logger.info("#{rsync_cmd}\n#{tmp_stdout}") unless tmp_stdout.empty?
      logger.error("#{rsync_cmd}\n#{tmp_stderr}") unless tmp_stderr.empty?
    }
    Dir.rmdir("#{EMPTY_DIR}")
  rescue Errno::EACCES, Errno::ENOENT, Errno::ENOTEMPTY, Exception => e
    logger.fatal(e.to_s)
  end
end
logger.info("Finished running at: #{Time.now} - Execution time: #{run_time.to_s[0, 5]}")
