# Main Puppet manifest for storage provisioning system
# File: modules/storage_provisioning/manifests/init.pp

class storage_provisioning (
  String $storage_base = '/home/storage_users',
  String $log_dir      = '/var/log/storage-provisioning',
  String $backup_dir   = '/var/backups/deprovisioned_users',
  String $user_group   = 'storage_users',
) {

  # Detect mount point dynamically based on storage_base path
  $mount_point = $facts['mountpoints'] ? {
    undef   => '/',
    default => $facts['mountpoints'].reduce('/') |$result, $entry| {
      $mount = $entry[0]
      if $storage_base =~ /^${mount}/ and size($mount) > size($result) {
        $mount
      } else {
        $result
      }
    },
  }

  # Detect filesystem type for quota operations
  $fs_type = $facts['mountpoints'][$mount_point] ? {
    undef   => 'xfs',
    default => $facts['mountpoints'][$mount_point]['filesystem'] ? {
      'xfs'   => 'xfs',
      'ext4'  => 'ext4',
      'ext3'  => 'ext3',
      'btrfs' => 'btrfs',
      'zfs'   => 'zfs',
      default => 'xfs',
    },
  }

  # Build filesystem-aware quota check command for cron job
  $quota_check_cmd = $fs_type ? {
    'xfs'   => "/usr/sbin/xfs_quota -x -c 'report -h' ${mount_point} | /bin/awk 'NR>2 && \$4 > \$3*0.9 {print \"WARNING: User \" \$1 \" is at \" \$4 \" of \" \$3 \" quota\"}'",
    'ext4'  => "/usr/sbin/repquota -u ${mount_point} | /bin/awk 'NR>5 && \$3 > \$4*0.9 {print \"WARNING: User \" \$1 \" is at \" \$3 \"KB of \" \$4 \"KB quota\"}'",
    'ext3'  => "/usr/sbin/repquota -u ${mount_point} | /bin/awk 'NR>5 && \$3 > \$4*0.9 {print \"WARNING: User \" \$1 \" is at \" \$3 \"KB of \" \$4 \"KB quota\"}'",
    'btrfs' => "/bin/echo 'Btrfs quota check not implemented' # TODO: Add btrfs qgroup show parsing",
    'zfs'   => "/sbin/zfs get -H -o name,value quota ${mount_point} | /bin/awk '\$2 != \"none\" {print \"ZFS quota: \" \$1 \" = \" \$2}'",
    default => "/bin/echo 'Unknown filesystem type for quota checking'",
  }

  # Ensure required packages are installed
  $required_packages = $facts['os']['family'] ? {
    'RedHat' => ['xfsprogs', 'quota', 'audit', 'policycoreutils-python-utils'],
    'Debian' => ['xfsprogs', 'quota', 'auditd', 'policycoreutils-python-utils'],
    default  => ['xfsprogs', 'quota'],
  }

  package { $required_packages:
    ensure => installed,
  }

  # Create log directory
  file { $log_dir:
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  # Create password log (restricted access)
  file { "${log_dir}/passwords.log":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    require => File[$log_dir],
  }

  # Create provisioning log
  file { "${log_dir}/provisioning.log":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => File[$log_dir],
  }

  # Create backup directory
  file { $backup_dir:
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0700',
  }

  # Create storage base directory
  file { $storage_base:
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  # Ensure storage group exists
  group { $user_group:
    ensure => present,
    system => false,
  }

  # Create SSH deny configuration directory
  file { '/etc/ssh/sshd_config.d':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  # Create SSH deny configuration file
  file { '/etc/ssh/sshd_config.d/storage_users.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "# Managed by Puppet - Storage Users SSH Access Control\n",
    require => File['/etc/ssh/sshd_config.d'],
  }

  # Ensure SSHD service is running and reload on config changes
  service { 'sshd':
    ensure    => running,
    enable    => true,
    subscribe => File['/etc/ssh/sshd_config.d/storage_users.conf'],
  }

  # Create audit rules file if auditd is installed
  if $facts['packages']['audit'] {
    file { '/etc/audit/rules.d/storage_users.rules':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0640',
      content => "# Managed by Puppet - Storage Users Audit Rules\n",
    }

    # Define reload command for audit rules
    exec { 'reload_audit_rules':
      command     => '/sbin/augenrules --load',
      refreshonly => true,
      require     => File['/etc/audit/rules.d/storage_users.rules'],
    }

    # Ensure auditd is running
    service { 'auditd':
      ensure => running,
      enable => true,
    }
  }

  # Verify quota support on filesystem
  exec { 'check_quota_support':
    command => '/bin/true',
    unless  => "/bin/mount | /bin/grep ' / ' | /bin/grep -qE 'usrquota|uquota'",
    require => Package[$required_packages],
  }

  # Log rotation for provisioning logs
  file { '/etc/logrotate.d/storage-provisioning':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => @(END),
      ${log_dir}/*.log {
          daily
          rotate 30
          compress
          delaycompress
          missingok
          notifempty
          create 0644 root root
      }
      | END
    require => File[$log_dir],
  }

  # Cron job to check quota usage and alert (filesystem-aware)
  cron { 'check_storage_quotas':
    command => "${quota_check_cmd} >> ${log_dir}/quota-alerts.log 2>&1",
    user    => 'root',
    hour    => '*/6',
    minute  => '0',
    require => File[$log_dir],
  }

  # Cleanup old backups (older than 90 days)
  cron { 'cleanup_old_backups':
    command => "/usr/bin/find ${backup_dir} -name '*.tar.gz' -mtime +90 -delete",
    user    => 'root',
    hour    => '2',
    minute  => '0',
    weekday => '0',
    require => File[$backup_dir],
  }
}