# Example Puppet site manifest
# File: manifests/site.pp or modules/storage_provisioning/examples/site.pp

# Initialize the storage provisioning system
class { 'storage_provisioning':
  storage_base => '/home/storage_users',
  user_group   => 'storage_users',
  log_dir      => '/var/log/storage-provisioning',
  backup_dir   => '/var/backups/deprovisioned_users',
}

# Example 1: Basic user with default 10G quota
storage_provisioning::user { 'john_doe':
  username => 'john_doe',
}

# Example 2: User with custom quota
storage_provisioning::user { 'jane_smith':
  username => 'jane_smith',
  quota    => '50G',
}

# Example 3: User with SSH access allowed
storage_provisioning::user { 'admin_user':
  username   => 'admin_user',
  quota      => '100G',
  allow_ssh  => true,
}

# Example 4: User with custom subdirectories
storage_provisioning::user { 'developer':
  username => 'developer',
  quota    => '25G',
  subdirs  => ['code', 'builds', 'logs', 'documentation'],
}

# Example 5: User with pre-hashed password (for automation)
storage_provisioning::user { 'service_account':
  username      => 'service_account',
  quota         => '15G',
  password_hash => '$6$rounds=656000$YourHashedPasswordHere',
  force_password_change => false,
}

# Example 6: Multiple users from Hiera data
# In hiera.yaml or common.yaml:
# ---
# storage_provisioning::users:
#   alice:
#     quota: '20G'
#   bob:
#     quota: '30G'
#     allow_ssh: true
#   charlie:
#     quota: '10G'

# Then in your manifest:
# $users = lookup('storage_provisioning::users', Hash, 'hash', {})
# $users.each |$username, $params| {
#   storage_provisioning::user { $username:
#     * => $params,
#   }
# }

# Example 7: Using arrays for batch provisioning
$standard_users = ['user1', 'user2', 'user3']
$standard_users.each |$user| {
  storage_provisioning::user { $user:
    username => $user,
    quota    => '10G',
  }
}

# Example 8: Different user tiers
$basic_tier_users = {
  'basic1' => '5G',
  'basic2' => '5G',
}

$premium_tier_users = {
  'premium1' => '50G',
  'premium2' => '50G',
}

$basic_tier_users.each |$username, $quota| {
  storage_provisioning::user { $username:
    username => $username,
    quota    => $quota,
  }
}

$premium_tier_users.each |$username, $quota| {
  storage_provisioning::user { $username:
    username   => $username,
    quota      => $quota,
    allow_ssh  => true,
  }
}