# Puppet Setup and Configuration Guide

## What is Puppet?

Puppet is an **Infrastructure as Code (IaC)** tool that automates system configuration and management. Instead of manually running commands on each server, you declare the desired state of your infrastructure, and Puppet ensures all systems match that configuration.

### Key Concepts

**Declarative Language** — You describe *what* you want, not *how* to achieve it:

```puppet
# Instead of: "Run this command to create a user"
# You write: "This user should exist with these properties"
user { 'alice':
  ensure => present,
  uid    => 1001,
  home   => '/home/alice',
}
```

**Idempotent** — Safe to run repeatedly. Puppet only makes changes if the current state differs from the desired state.

**Agent-Based** — Puppet agent runs on each managed node and reports back to a central Puppet server (or can run standalone).

### Puppet vs Bash Scripts

| Feature | Puppet | Bash Scripts |
|---------|--------|--------------|
| Declarative | Yes | No (imperative) |
| Idempotent | Yes | No (must handle state) |
| Cross-platform | Yes | No (OS-specific) |
| Error handling | Built-in | Manual |
| Scale | Hundreds of servers | Limited |
| Reusability | High (modules) | Low |

## Project Structure

```
storage-provisioning/
├── modules/
│   └── storage_provisioning/
│       ├── manifests/
│       │   ├── init.pp          # Main class
│       │   └── user.pp          # User definition
│       ├── templates/
│       │   └── README.txt.epp   # User README template
│       └── files/
├── manifests/
│   └── site.pp                 # Site manifest (applies classes to nodes)
├── tests/
│   └── test_provisioning.sh
├── scripts/
│   ├── provision_user.sh
│   ├── deprovision_user.sh
│   └── utils.sh
└── puppet_setup.md
```

## Understanding the Manifests

### Main Class (`init.pp`)

This file sets up the infrastructure for the entire storage provisioning system:

```puppet
class storage_provisioning (
  String $storage_base = '/home/storage_users',
  String $log_dir      = '/var/log/storage-provisioning',
  ...
)
```

**What it does:**

1. **Installs packages** — `xfsprogs`, `quota`, `audit`, etc. (OS-aware)
2. **Creates directories** — Log directory, backup directory, storage base
3. **Creates log files** — With proper permissions (restricted for passwords)
4. **Configures SSH** — Creates SSH deny configuration for storage users
5. **Sets up auditing** — Enables audit rules for compliance
6. **Configures log rotation** — Keeps logs manageable (30-day retention)
7. **Creates cron jobs** — Automated quota monitoring and backup cleanup

**Example parameters:**

```puppet
class { 'storage_provisioning':
  storage_base => '/mnt/storage_users',  # Custom storage location
  log_dir      => '/var/log/app-storage',
  backup_dir   => '/backups/deprovisioned',
}
```

### User Definition (`user.pp`)

This is a **custom resource definition** that creates and configures individual users:

```puppet
storage_provisioning::user { 'alice':
  quota     => '100G',
  allow_ssh => true,
}
```

**What it does for each user:**

1. **Validates input** — Checks username format and quota format
2. **Creates user account** — With home directory and default shell
3. **Generates password** — Secure random 16-character password
4. **Sets permissions** — Home directory `700`, subdirs `755`
5. **Creates subdirectories** — `data/`, `backups/`, `temp/`, `logs/`
6. **Creates README** — Personalized user guide with quota info
7. **Sets disk quota** — XFS or ext4, depending on filesystem
8. **Configures SSH** — Denies SSH access by default
9. **Adds audit rules** — If auditd is available
10. **Sets SELinux context** — If SELinux is enabled

## Installation

### Install Puppet Agent

On Rocky Linux:

```bash
# Add Puppet repository
sudo rpm -Uvh https://yum.puppet.com/puppet7-release-el-9.noarch.rpm

# Install Puppet agent
sudo dnf install -y puppet-agent

# Add puppet to PATH
export PATH=/opt/puppetlabs/bin:$PATH
```

On Ubuntu/Debian:

```bash
# Add Puppet repository
wget https://apt.puppet.com/puppet7-release-focal.deb
sudo dpkg -i puppet7-release-focal.deb
sudo apt-get update

# Install Puppet agent
sudo apt-get install -y puppet-agent

# Add puppet to PATH
export PATH=/opt/puppetlabs/bin:$PATH
```

### Verify Installation

```bash
puppet --version
# Should output: 7.x.x
```

## Setup for Your Project

### Step 1: Copy Module to Puppet Directory

```bash
# Create module directory
sudo mkdir -p /etc/puppetlabs/code/environments/production/modules/storage_provisioning

# Copy your manifests
sudo cp modules/storage_provisioning/manifests/* \
  /etc/puppetlabs/code/environments/production/modules/storage_provisioning/manifests/

# Copy templates (if you have them)
sudo cp modules/storage_provisioning/templates/* \
  /etc/puppetlabs/code/environments/production/modules/storage_provisioning/templates/
```

### Step 2: Create Site Manifest

Create `/etc/puppetlabs/code/environments/production/manifests/site.pp`:

```puppet
# Apply storage provisioning to all nodes
node default {
  include storage_provisioning
}
```

### Step 3: Test the Manifest

**Syntax check:**

```bash
puppet parser validate /etc/puppetlabs/code/environments/production/manifests/site.pp
```

**Dry run (no changes):**

```bash
sudo puppet apply --noop /etc/puppetlabs/code/environments/production/manifests/site.pp
```

### Step 4: Apply the Manifest

```bash
sudo puppet apply /etc/puppetlabs/code/environments/production/manifests/site.pp
```

## Usage Examples

### Example 1: Create a Single User

Edit your site manifest to include:

```puppet
node default {
  include storage_provisioning

  storage_provisioning::user { 'alice':
    quota     => '100G',
    allow_ssh => true,
  }
}
```

Apply:

```bash
sudo puppet apply /etc/puppetlabs/code/environments/production/manifests/site.pp
```

### Example 2: Create Multiple Users

```puppet
node default {
  include storage_provisioning

  storage_provisioning::user { 'alice':
    quota     => '100G',
    allow_ssh => true,
  }

  storage_provisioning::user { 'bob':
    quota => '50G',
  }

  storage_provisioning::user { 'charlie':
    quota                => '200G',
    force_password_change => false,
  }

  storage_provisioning::user { 'diana':
    quota   => '25G',
    user_group => 'developers',  # Custom group
  }
}
```

### Example 3: Custom Configuration

```puppet
node default {
  class { 'storage_provisioning':
    storage_base => '/mnt/enterprise_storage',
    log_dir      => '/var/log/enterprise-provisioning',
    backup_dir   => '/backups/users',
  }

  storage_provisioning::user { 'admin_user':
    quota           => '500G',
    allow_ssh       => true,
    subdirs         => ['projects', 'data', 'archive'],  # Custom subdirs
    force_password_change => false,
  }
}
```

## Available Parameters

### `storage_provisioning::user` Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `username` | String | (required) | Username to create |
| `quota` | String | `10G` | Disk quota (e.g., 5G, 500M, 1T) |
| `storage_base` | String | `/home/storage_users` | Base directory for users |
| `user_group` | String | `storage_users` | Primary group |
| `allow_ssh` | Boolean | `false` | Allow SSH access |
| `password_hash` | String | (generated) | Pre-set password hash |
| `force_password_change` | Boolean | `true` | Force change on first login |
| `subdirs` | Array | `['data', 'backups', 'temp', 'logs']` | Subdirectories to create |

### `storage_provisioning` Class Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `storage_base` | String | `/home/storage_users` | Base storage directory |
| `log_dir` | String | `/var/log/storage-provisioning` | Log directory |
| `backup_dir` | String | `/var/backups/deprovisioned_users` | Backup directory |
| `user_group` | String | `storage_users` | Default user group |

## Puppet Commands

### Apply Manifest

```bash
# Apply locally (standalone mode)
sudo puppet apply /path/to/manifest.pp

# Dry run (no changes)
sudo puppet apply --noop /path/to/manifest.pp

# Verbose output
sudo puppet apply -v /path/to/manifest.pp

# Debug mode
sudo puppet apply -d /path/to/manifest.pp
```

### Validate Syntax

```bash
puppet parser validate /path/to/manifest.pp
```

### List Resources

```bash
# Show all resources on the system
sudo puppet resource service

# Show specific resource
sudo puppet resource user alice
```

## Troubleshooting

### "Module not found"

**Problem**: Puppet can't find `storage_provisioning` module.

**Solution**: Ensure module is in correct location:

```bash
ls /etc/puppetlabs/code/environments/production/modules/storage_provisioning/manifests/
# Should show: init.pp, user.pp
```

### "Syntax error"

**Problem**: Manifest has syntax errors.

**Solution**: Validate syntax:

```bash
puppet parser validate your_manifest.pp
# Shows line numbers and errors
```

### "Permission denied"

**Problem**: Puppet needs sudo to make system changes.

**Solution**: Always run with `sudo`:

```bash
sudo puppet apply your_manifest.pp
```

### Quota not set

**Problem**: Quotas enabled but not applying.

**Solution**: Verify quota support:

```bash
mount | grep ' / ' | grep -E 'usrquota|uquota'
# Should show quota options
```

## Comparing Approaches

### Bash Scripts vs Puppet

**Use bash scripts (`provision_user.sh`) when:**
- Provisioning a small number of users
- Need quick, one-off changes
- Don't need centralized management
- Testing individual features

**Use Puppet when:**
- Managing many servers and users
- Need consistent configuration across infrastructure
- Want version control and change tracking
- Need to audit and enforce compliance
- Building enterprise infrastructure

### Combined Approach

The best practice is to **use both**:

```
┌──────────────────────────────┐
│  Puppet (Infrastructure)     │
│  - Manages entire system     │
│  - Enforces configuration    │
│  - Runs regularly            │
└──────────────────────────────┘
         ↓
┌──────────────────────────────┐
│  Bash Scripts (Operations)   │
│  - Manual provisioning       │
│  - Quick testing             │
│  - Emergency procedures      │
└──────────────────────────────┘
```

## Next Steps

1. **Copy modules to Puppet directory** — Make them available to Puppet
2. **Create site.pp** — Define your infrastructure
3. **Test with `--noop`** — Dry run before applying
4. **Apply the manifest** — Create users and resources
5. **Monitor logs** — Check `/var/log/storage-provisioning/`
6. **Verify users** — Test with `id` and quota commands

## Additional Resources

- [Puppet Documentation](https://puppet.com/docs/puppet/latest/)
- [Puppet Language Reference](https://puppet.com/docs/puppet/latest/lang_summary.html)
- [Puppet Best Practices](https://puppet.com/docs/puppet/latest/style_guide.html)
- Main setup guide: `setup.md`
- Provision script guide: `provision_user.md`
- Deprovision script guide: `deprovision_user.md`