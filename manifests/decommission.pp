# Puppet manifest for deprovisioning storage users
# File: modules/storage_provisioning/manifests/decommission.pp

define storage_provisioning::decommission (
  String $username                = $title,
  String $storage_base            = '/home/storage_users',
  String $backup_dir              = '/var/backups/deprovisioned_users',
  Boolean $create_backup          = true,
  Integer $retention_days         = 30,
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

  # Detect filesystem type
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

  # Build filesystem-aware quota removal command
  $quota_remove_cmd = $fs_type ? {
    'xfs'   => "/usr/sbin/xfs_quota -x -c 'limit bsoft=0 bhard=0 ${username}' ${mount_point}",
    'ext4'  => "/usr/sbin/setquota -u ${username} 0 0 0 0 ${mount_point}",
    'ext3'  => "/usr/sbin/setquota -u ${username} 0 0 0 0 ${mount_point}",
    'btrfs' => "/bin/true",  # Btrfs quotas are removed with subvolume
    'zfs'   => "/bin/true",  # ZFS quotas are removed with dataset
    default => "/bin/true",
  }

  # Validate username exists
  if !defined(User[$username]) {
    notice("User ${username} does not exist in Puppet catalog")
  }

  # Create backup before deletion
  if $create_backup {
    $timestamp = strftime('%Y%m%d_%H%M%S')
    $backup_file = "${backup_dir}/${username}_${timestamp}.tar.gz"
    $user_home = "${storage_base}/${username}"

    # Ensure backup directory exists
    file { $backup_dir:
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0700',
    }

    # Create backup archive
    exec { "backup_user_${username}":
      command => "/bin/tar -czf ${backup_file} -C ${storage_base} ${username}",
      onlyif  => "/usr/bin/test -d ${user_home}",
      require => File[$backup_dir],
      before  => [
        User[$username],
        File[$user_home],
      ],
    }

    # Create metadata file
    $metadata_content = @("END")
      Username: ${username}
      Deprovisioned: ${timestamp}
      Home Directory: ${user_home}
      Backup File: ${backup_file}
      Retention Days: ${retention_days}
      Expires: ${strftime('%Y-%m-%d', Integer(inline_template('<%= Time.now.to_i + ${retention_days} * 86400 %>')))}
      | END

    file { "${backup_file}.meta":
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0600',
      content => $metadata_content,
      require => Exec["backup_user_${username}"],
    }

    # Log backup creation
    exec { "log_backup_${username}":
      command     => "/bin/echo '[PUPPET] Backup created for ${username}: ${backup_file}' >> /var/log/storage-provisioning/provisioning.log",
      require     => Exec["backup_user_${username}"],
      refreshonly => true,
      subscribe   => Exec["backup_user_${username}"],
    }
  }

  # Kill user processes
  exec { "kill_processes_${username}":
    command => "/usr/bin/pkill -TERM -u ${username} || /bin/true",
    onlyif  => "/usr/bin/pgrep -u ${username}",
    before  => User[$username],
  }

  # Wait for graceful shutdown
  exec { "wait_process_exit_${username}":
    command => "/bin/sleep 2",
    require => Exec["kill_processes_${username}"],
    before  => User[$username],
  }

  # Force kill any remaining processes
  exec { "force_kill_processes_${username}":
    command => "/usr/bin/pkill -KILL -u ${username} || /bin/true",
    onlyif  => "/usr/bin/pgrep -u ${username}",
    require => Exec["wait_process_exit_${username}"],
    before  => User[$username],
  }

  # Remove quota (filesystem-aware)
  exec { "remove_quota_${username}":
    command => "${quota_remove_cmd} || /bin/true",
    onlyif  => "/usr/bin/id ${username}",
    before  => User[$username],
  }

  # Remove cron jobs
  exec { "remove_cron_${username}":
    command => "/usr/bin/crontab -u ${username} -r || /bin/true",
    onlyif  => "/usr/bin/crontab -u ${username} -l",
    before  => User[$username],
  }

  # Remove from SSH deny list
  file_line { "remove_ssh_deny_${username}":
    ensure            => absent,
    path              => '/etc/ssh/sshd_config.d/storage_users.conf',
    match             => "^DenyUsers.*${username}.*$",
    match_for_absence => true,
    notify            => Service['sshd'],
  }

  # Remove audit rule
  file_line { "remove_audit_rule_${username}":
    ensure            => absent,
    path              => '/etc/audit/rules.d/storage_users.rules',
    match             => "storage_access_${username}",
    match_for_absence => true,
    notify            => Exec['reload_audit_rules'],
  }

  # Remove mail spool
  file { "/var/mail/${username}":
    ensure => absent,
    force  => true,
  }

  # Remove home directory
  file { "${storage_base}/${username}":
    ensure  => absent,
    force   => true,
    recurse => true,
    backup  => false,
  }

  # Remove user account
  user { $username:
    ensure     => absent,
    managehome => false,  # We handle home directory separately
    require    => [
      Exec["force_kill_processes_${username}"],
      Exec["remove_quota_${username}"],
      Exec["remove_cron_${username}"],
      File["${storage_base}/${username}"],
    ],
  }

  # Log deprovisioning
  exec { "log_deprovisioning_${username}":
    command => "/bin/echo '[PUPPET] User ${username} deprovisioned' >> /var/log/storage-provisioning/provisioning.log",
    require => User[$username],
  }
}

# Example usage in site.pp:
#
# To deprovision a user:
# storage_provisioning::decommission { 'old_user':
#   username       => 'old_user',
#   create_backup  => true,
#   retention_days => 90,
# }
#
# Or simply remove the storage_provisioning::user declaration
# and add the decommission one