# Main Puppet manifest for storage provisioning system
# File: modules/storage_provisioning/manifests/init.pp

class storage_provisioning (
  String $storage_base = '/home/storage_users',
  String $log_dir      = '/var/log/storage-provisioning',
  String $backup_dir   = '/var/backups/deprovisioned_users',
  String $user_group   = 'storage_users',
) {

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

  # Cron job to check quota usage and alert
  cron { 'check_storage_quotas':
    command => "/usr/sbin/xfs_quota -x -c 'report -h' / | /bin/awk '\$4 > \$3*0.9 {print \"WARNING: User \" \$1 \" is at \" \$4 \" of \" \$3 \" quota\"}' >> ${log_dir}/quota-alerts.log",
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