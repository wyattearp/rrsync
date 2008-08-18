#!/usr/bin/ruby
require 'rubygems'
require 'Logger'
require 'open4'
require 'benchmark'
require 'ping'

#============================= OPTIONS ==============================#
# == Options for local machine.
SSH_APP       = '/usr/bin/ssh'
RSYNC_APP     = '/opt/local/bin/rsync'

EXCLUDE_FILE  = '/path/to/.rsyncignore'
DIR_TO_BACKUP = '/folder/to/backup'
LOG_FILE      = '/tmp/backup_home.log'
LOG_AGE       = 'daily'

EMPTY_DIR     = '/tmp/empty_rsync_dir/' #NEEDS TRAILING SLASH.
# == Options for the remote machine.
SSH_USER      = 'USER'
SSH_SERVER    = 'HOSTNAME or IP'
SSH_PORT      = '' #Leave blank for default (port 22).
BACKUP_ROOT   = '/path/on/remote/machine/to/backup/folder'
BACKUP_DIR    = BACKUP_ROOT + '/' + Time.now.strftime('%A').downcase
RSYNC_VERBOSE = '--progress'
RSYNC_OPTS    = "--force --ignore-errors --delete-excluded --exclude-from=#{EXCLUDE_FILE} --delete --backup --backup-dir=#{BACKUP_DIR} -a"
# == Options to control output
DEBUG         = true #If true output to screen else output is sent to log file.
SLIENT        = false #Totall slient = no log or screen output.
#========================== END OF OPTIONS ==========================#

if DEBUG && !SLIENT
  logger = Logger.new(STDOUT, LOG_AGE)
elsif LOG_FILE != '' && !SLIENT
  logger = Logger.new(LOG_FILE, LOG_AGE)
else
  logger = Logger.new(nil)
end
ssh_port = SSH_PORT == '' ? '' : "-e 'ssh -p #{SSH_PORT}'"
rsync_cleanout_cmd = "#{RSYNC_APP} #{RSYNC_VERBOSE} #{ssh_port} --delete -a #{EMPTY_DIR} #{SSH_USER}@#{SSH_SERVER}:#{BACKUP_DIR}"
rsync_cmd = "#{RSYNC_APP} #{RSYNC_VERBOSE} #{ssh_port} #{RSYNC_OPTS} #{DIR_TO_BACKUP} #{SSH_USER}@#{SSH_SERVER}:#{BACKUP_ROOT}/current"

logger.info("Started running at: #{Time.now}")
run_time = Benchmark.realtime do
  begin
    raise Exception, "Unable to find remote host (#{SSH_SERVER})" unless Ping.pingecho(SSH_SERVER)
       
    FileUtils.mkdir("#{EMPTY_DIR}") unless File.exist?("#{EMPTY_DIR}")
    Open4::popen4("#{rsync_cleanout_cmd}") { |pid, stdin, stdout, stderr|
      tmp_stdout = stdout.read.strip
      tmp_stderr = stderr.read.strip
      logger.info("#{rsync_cleanout_cmd}\n#{tmp_stdout}") unless tmp_stdout == ''
      logger.error("#{rsync_cleanout_cmd}\n#{tmp_stderr}") unless tmp_stderr == ''
    }
    Open4::popen4("#{rsync_cmd}") { |pid, stdin, stdout, stderr|
      tmp_stdout = stdout.read.strip
      tmp_stderr = stderr.read.strip
      logger.info("#{rsync_cmd}\n#{tmp_stdout}") unless tmp_stdout == ''
      logger.error("#{rsync_cmd}\n#{tmp_stderr}") unless tmp_stderr == ''
    }
  rescue Errno::EACCES, Errno::ENOENT, Exception => e
    logger.fatal(e.to_s)
  end
end
logger.info("Finished running at: #{Time.now} - Execution time: #{run_time.to_s[0, 5]}")