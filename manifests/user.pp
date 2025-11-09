# Puppet manifest for storage user provisioning
# File: modules/storage_provisioning/manifests/user.pp

define storage_provisioning::user (
  String $username                = $title,
  String $quota                   = '10G',
  String $storage_base            = '/home/storage_users',
  String $user_group              = 'storage_users',
  Boolean $allow_ssh              = false,
  Optional[String] $password_hash = undef,
  Boolean $force_password_change  = true,
  Array[String] $subdirs          = ['data', 'backups', 'temp', 'logs'],
) {

  # Validate username format
  if $username !~ /^[a-z][a-z0-9_-]{2,15}$/ {
    fail("Invalid username: ${username}. Must be 3-16 chars, start with lowercase letter.")
  }

  # Validate quota format
  if $quota !~ /^[0-9]+[MGT]$/ {
    fail("Invalid quota format: ${quota}. Use format like 10G, 500M, 1T")
  }

  # Ensure storage base directory exists
  if !defined(File[$storage_base]) {
    file { $storage_base:
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }
  }

  # Ensure storage group exists
  if !defined(Group[$user_group]) {
    group { $user_group:
      ensure => present,
      system => false,
    }
  }

  # Generate random password if not provided
  $temp_password = $password_hash ? {
    undef   => fqdn_rand_string(16, '', "${username}-${storage_base}"),
    default => undef,
  }

  # Create user account
  user { $username:
    ensure     => present,
    gid        => $user_group,
    home       => "${storage_base}/${username}",
    managehome => true,
    shell      => '/bin/bash',
    password   => $password_hash,
    comment    => "Storage user - ${username}",
    require    => [
      Group[$user_group],
      File[$storage_base],
    ],
  }

  # Set initial password if generated
  if $temp_password {
    exec { "set_password_${username}":
      command => "/bin/echo '${username}:${temp_password}' | /usr/sbin/chpasswd",
      unless  => "/usr/bin/passwd -S ${username} | /bin/grep -qv 'LK'",
      require => User[$username],
      notify  => Exec["log_temp_password_${username}"],
    }

    # Log temporary password securely
    exec { "log_temp_password_${username}":
      command     => "/bin/echo '[PUPPET] Temporary password for ${username}: ${temp_password}' >> /var/log/storage-provisioning/passwords.log",
      refreshonly => true,
      require     => File['/var/log/storage-provisioning'],
    }

    # Force password change on first login
    if $force_password_change {
      exec { "force_password_change_${username}":
        command => "/usr/bin/chage -d 0 ${username}",
        unless  => "/usr/bin/chage -l ${username} | /bin/grep -q 'Last password change.*Jan 01, 1970'",
        require => User[$username],
      }
    }
  }

  # Set home directory permissions (strict)
  file { "${storage_base}/${username}":
    ensure  => directory,
    owner   => $username,
    group   => $user_group,
    mode    => '0700',
    require => User[$username],
  }

  # Create subdirectories with appropriate permissions
  $subdirs.each |$subdir| {
    file { "${storage_base}/${username}/${subdir}":
      ensure  => directory,
      owner   => $username,
      group   => $user_group,
      mode    => '0755',
      require => File["${storage_base}/${username}"],
    }
  }

  # Create README file
  file { "${storage_base}/${username}/README.txt":
    ensure  => file,
    owner   => $username,
    group   => $user_group,
    mode    => '0644',
    content => epp('storage_provisioning/README.txt.epp', {
      'username' => $username,
      'quota'    => $quota,
      'subdirs'  => $subdirs,
    }),
    require => File["${storage_base}/${username}"],
  }

  # Detect filesystem type and mount point
  $mount_point = '/'  # You might want to make this dynamic
  $fs_type = $facts['filesystems'] ? {
    /xfs/  => 'xfs',
    /ext4/ => 'ext4',
    default => 'xfs',
  }

  # Set quota based on filesystem type
  case $fs_type {
    'xfs': {
      # Check if quotas are enabled
      exec { "check_xfs_quota_enabled_${username}":
        command => '/bin/true',
        unless  => "/bin/mount | /bin/grep ' / ' | /bin/grep -qE 'usrquota|uquota'",
        require => User[$username],
        notify  => Exec["set_xfs_quota_${username}"],
      }

      exec { "set_xfs_quota_${username}":
        command     => "/usr/sbin/xfs_quota -x -c 'limit bsoft=${quota} bhard=${quota} ${username}' ${mount_point}",
        refreshonly => false,
        require     => [
          User[$username],
          Exec["check_xfs_quota_enabled_${username}"],
        ],
        notify      => Exec["log_quota_set_${username}"],
      }
    }
    'ext4': {
      # Convert quota to KB for setquota
      $quota_kb = $quota ? {
        /^(\d+)M$/ => $1 * 1024,
        /^(\d+)G$/ => $1 * 1024 * 1024,
        /^(\d+)T$/ => $1 * 1024 * 1024 * 1024,
        default    => 10 * 1024 * 1024,  # Default 10GB
      }

      exec { "set_ext4_quota_${username}":
        command => "/usr/sbin/setquota -u ${username} ${quota_kb} ${quota_kb} 0 0 ${mount_point}",
        unless  => "/usr/sbin/quota -u ${username} | /bin/grep -q ${username}",
        require => User[$username],
        notify  => Exec["log_quota_set_${username}"],
      }
    }
    default: {
      warning("Filesystem type ${fs_type} may not support quotas")
    }
  }

  # Log quota setting
  exec { "log_quota_set_${username}":
    command     => "/bin/echo '[PUPPET] Set quota ${quota} for ${username}' >> /var/log/storage-provisioning/provisioning.log",
    refreshonly => true,
    require     => File['/var/log/storage-provisioning'],
  }

  # SSH access control
  if !$allow_ssh {
    # Add to SSH deny list
    file_line { "deny_ssh_${username}":
      path    => '/etc/ssh/sshd_config.d/storage_users.conf',
      line    => "DenyUsers ${username}",
      require => User[$username],
      notify  => Service['sshd'],
    }
  }

  # Audit logging (if auditd is installed)
  if $facts['packages']['audit'] {
    file_line { "audit_rule_${username}":
      path    => '/etc/audit/rules.d/storage_users.rules',
      line    => "-w ${storage_base}/${username} -p wa -k storage_access_${username}",
      require => File["${storage_base}/${username}"],
      notify  => Exec['reload_audit_rules'],
    }
  }

  # SELinux context (if SELinux is enabled)
  if $facts['selinux'] {
    exec { "restorecon_${username}":
      command     => "/sbin/restorecon -R ${storage_base}/${username}",
      refreshonly => true,
      subscribe   => File["${storage_base}/${username}"],
    }
  }
}