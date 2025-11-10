# Architecture: Automated Storage Provisioning Tool

## Overview

The Automated Storage Provisioning Tool is a containerized, enterprise-grade system for managing user accounts, storage directories, disk quotas, and access controls on Rocky Linux. This document describes the system design, components, data flow, and deployment model.

**Target Environment:** Rocky Linux 8/9 virtual machines with XFS filesystems  
**Automation Framework:** Puppet + Bash scripts  
**Use Case:** Multi-user environments requiring consistent, auditable storage management

## System Architecture Diagram

```mermaid
graph TB
    subgraph Host["Host Machine"]
        direction LR
        Repo["Project Repository"]
        Scripts["scripts/"]
        Manifests["manifests/"]
        Docs["docs/"]
        Tests["tests/"]
        
        Repo --> Scripts
        Repo --> Manifests
        Repo --> Docs
        Repo --> Tests
    end
    
    Host -->|"rsync / SCP"| Deploy["Deploy"]
    
    subgraph VM["Rocky Linux VM"]
        direction TB
        
        subgraph Runtime["Orchestration"]
            Puppet["Puppet Agent"]
            Bash["Bash Runtime"]
            Puppet --> Bash
        end
        
        subgraph System["System Components"]
            UserMgmt["User Management<br/>useradd/userdel<br/>PAM"]
            QuotaMgmt["Quota System<br/>xfs_quota<br/>setquota"]
            StorageMgmt["Storage<br/>/home/storage_users<br/>XFS filesystem"]
            AccessCtrl["Access Control<br/>SSH/SFTP<br/>SELinux"]
        end
        
        subgraph Storage["Persistent Storage"]
            UserDirs["User Directories<br/>/home/storage_users/{user}/"]
            Logs["System Logs<br/>/var/log/storage-provisioning/"]
            Backups["Backups<br/>/var/backups/deprovisioned_users/"]
        end
        
        Runtime --> System
        System --> Storage
    end
    
    VM --> Result["Provisioned Users<br/>Quotas Applied<br/>Access Configured"]
```

## Component Hierarchy

```mermaid
graph TB
    subgraph L1["Level 1: Entrypoints"]
        CLI["CLI Scripts<br/>provision_user.sh<br/>deprovision_user.sh"]
        Puppet_UI["Puppet Manifests<br/>init.pp<br/>user.pp"]
        Batch["Batch Operations<br/>users.txt loop"]
    end
    
    subgraph L2["Level 2: Orchestration"]
        Prov["Provisioning Engine"]
        Deprov["Deprovisioning Engine"]
        Utils["Utilities<br/>Logging / Validation"]
    end

    %% Level 3: System Tools
    subgraph L3["Level 3: System Tools"]
        subgraph UserMgmt["User & Group Tools"]
            UserTools["useradd / userdel / usermod"]
            GroupTools["groupadd / groupmod"]
        end
        subgraph Quotas["Quota Management"]
            QuotaTools["xfs_quota / setquota"]
        end
        subgraph FileOps["Filesystem Tools"]
            FileTools["mkdir / chown / chmod"]
        end
        subgraph SSH["SSH & Access"]
            SSH_Tools["sshd / SSH Keys"]
        end
        subgraph Audit["Audit & Logging"]
            Audit_Tools["auditd / syslog"]
        end
    end

    %% Level 4: Storage
    subgraph L4["Level 4: Storage"]
        Storage["User Homes / Logs / Backups"]
    end

    %% Connections
    L1 --> |CLI| L2
    L2 --> |Orchestrates| L3
    L3 --> |Manages| L4

    %% Styling for colored borders
    style L1 stroke:#1e88e5,stroke-width:2px,fill:none,color:#1e88e5
    style L2 stroke:#8e24aa,stroke-width:2px,fill:none,color:#8e24aa
    style L3 stroke:#fb8c00,stroke-width:2px,fill:none,color:#fb8c00
    style L4 stroke:#43a047,stroke-width:2px,fill:none,color:#43a047
```

## Data Flow: Provisioning User

```mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'background': 'transparent', 'noteBkgColor': 'transparent' }}}%%
sequenceDiagram
    actor Admin
    participant Script as provision_user.sh
    participant System as Linux System
    participant FS as XFS Filesystem
    participant Log as Logs

    Admin->>Script: ./provision_user.sh alice -q 10G
    
    rect stroke:#1e88e5,stroke-width:3px,fill:none
    Note over Script: Validation Phase
    Script->>Script: Validate username format
    Script->>Script: Validate quota format
    Script->>System: Check if user exists
    end
    
    rect stroke:#43a047,stroke-width:3px,fill:none
    Note over Script: User Creation Phase
    Script->>System: useradd alice
    Script->>System: groupadd storage_users
    Script->>System: Generate temp password
    end
    
    rect stroke:#ffc107,stroke-width:3px,fill:none
    Note over Script: Directory Setup Phase
    Script->>FS: mkdir /home/storage_users/alice
    Script->>FS: chown alice:storage_users
    Script->>FS: chmod 700
    Script->>FS: Create subdirs (data,backups,temp,logs)
    end
    
    rect stroke:#f44336,stroke-width:3px,fill:none
    Note over Script: Quota Enforcement Phase
    Script->>System: xfs_quota set 10G limit
    Script->>System: xfs_quota verify
    end
    
    rect stroke:#9c27b0,stroke-width:3px,fill:none
    Note over Script: Access Control Phase
    Script->>System: SSH access: DENY
    Script->>System: Add SELinux context
    Script->>System: Add audit rules
    end
    
    Script->>Log: [INFO] User provisioned successfully
    Script->>Admin: Success + Temp Password
```

## Data Flow: Deprovisioning User

```mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'background': 'transparent', 'noteBkgColor': 'transparent' }}}%%
sequenceDiagram
    actor Admin
    participant Script as deprovision_user.sh
    participant System as Linux System
    participant FS as XFS Filesystem
    participant Backup as Backup System
    participant Log as Logs

    Admin->>Script: ./deprovision_user.sh alice --backup
    
    rect stroke:#f44336,stroke-width:3px,fill:none
    Note over Script: Safety Phase
    Script->>System: Verify user exists
    Script->>Admin: Display warning
    Script->>System: Check running processes
    Script->>System: Gather user info (UID, disk usage)
    end
    
    rect stroke:#ff9800,stroke-width:3px,fill:none
    Note over Script: Backup Phase
    Script->>System: Read /home/storage_users/alice
    Script->>Backup: tar -czf alice_TIMESTAMP.tar.gz
    Script->>Backup: Create alice_TIMESTAMP.tar.gz.meta
    Script->>Log: [INFO] Backup created
    end
    
    rect stroke:#3f51b5,stroke-width:3px,fill:none
    Note over Script: Account Termination Phase
    Script->>System: passwd -l alice (lock account)
    Script->>System: pkill -u alice (kill processes)
    Script->>System: usermod -s /sbin/nologin alice
    Script->>System: xfs_quota remove limits
    end
    
    rect stroke:#e91e63,stroke-width:3px,fill:none
    Note over Script: Cleanup Phase
    Script->>System: userdel -r alice
    Script->>System: rm -rf /home/storage_users/alice
    Script->>System: Remove SSH config
    Script->>System: Remove audit rules
    end
    
    Script->>Log: [INFO] User deprovisioned
    Script->>Admin: Deprovisioning complete
```

---

## Key Design Decisions

### 1. XFS + Quotas (Why XFS?)

**Decision:** Use XFS filesystem with user/group quotas.

**Rationale:**
- Rocky Linux default filesystem (modern, performant)
- Native project quota support (unlike ext4)
- Better for large files and concurrent I/O
- Tight integration with Linux enterprise tools

**Implementation:**
```bash
# /etc/fstab
/dev/mapper/rl-root / xfs defaults,usrquota,grpquota 0 0

# Verification
xfs_quota -x -c 'report -h' /
```

### 2. Bash + Puppet (Hybrid Approach)

**Decision:** Combine Bash scripts + Puppet manifests.

**Rationale:**

| Tool | Use Case |
|------|----------|
| **Bash** | Direct user provisioning, quick operations, testing |
| **Puppet** | Infrastructure-as-Code, multi-server deployment, idempotency |

**Benefit:** Flexibility for ad-hoc operations + consistency for bulk deployments.

### 3. Default Deny (SSH Access)

**Decision:** Disable SSH by default; enable on request.

**Rationale:**
- Security-first approach
- Reduces attack surface
- Admins explicitly enable per user
- Audit trail of who has access

### 4. Backup on Deprovision

**Decision:** Archive user data before deletion.

**Rationale:**
- Safety net for accidental deletions
- Legal/compliance requirements (data retention)
- Metadata tracking (audit trail)
- 30-day retention policy (configurable)

### 5. Centralized Logging

**Decision:** All operations logged to `/var/log/storage-provisioning/provisioning.log`.

**Rationale:**
- Single audit trail
- Timestamps + severity levels
- Searchable and parseable
- Integration with syslog/ELK (future)

---

## Security Model

### Authentication

| Method | Use | Status |
|--------|-----|--------|
| **Password** | Initial login | Temporary, force change |
| **SSH Keys** | Remote access | Optional, admin-enabled |
| **Puppet** | System automation | Runs as root with validation |

### Authorization

| Role | Permissions |
|------|-------------|
| **Admin** | Provision, deprovision, modify quotas |
| **User** | Read own files, write to own directory |
| **System** | Enforce quotas, prevent privilege escalation |

### Isolation

| Layer | Isolation Method |
|-------|------------------|
| **Filesystem** | User home directories (700 permissions) |
| **Process** | User cannot access other user data |
| **Quota** | Hard limits prevent disk exhaustion |
| **SSH/SFTP** | Chroot to user directory (optional) |
| **SELinux** | Custom contexts for storage paths |

### Audit Trail

```
Event                          → Logged To
─────────────────────────────────────────────
User provisioned              → /var/log/storage-provisioning/provisioning.log
User deprovisioned            → /var/log/storage-provisioning/provisioning.log
Directory accessed            → /var/audit/audit.log (auditd)
Quota exceeded                → /var/log/quota.log
SSH access attempt            → /var/log/auth.log
```

---

## Operational Workflows

### Workflow 1: Single User Provisioning

```mermaid
graph LR
    A["Admin: provision_user.sh alice"] --> B["Validate Input"]
    B --> C["Create User"]
    C --> D["Create Directory"]
    D --> E["Apply Quota"]
    E --> F["Configure Access"]
    F --> G["Log & Report"]
    G --> H["alice provisioned"]
    
    style A stroke:#1e88e5,stroke-width:2px,fill:none
    style H stroke:#43a047,stroke-width:2px,fill:none
    style B stroke:#ffc107,stroke-width:2px,fill:none
    style C stroke:#ff9800,stroke-width:2px,fill:none
    style E stroke:#f44336,stroke-width:2px,fill:none
```

### Workflow 2: Batch Provisioning

```mermaid
graph TD
    A["Create users.txt<br/>alice<br/>bob<br/>charlie"] --> B["for each user in file"]
    B --> C["provision_user.sh"]
    C --> D1["alice: 5GB quota"]
    C --> D2["bob: 5GB quota"]
    C --> D3["charlie: 5GB quota"]
    
    style A stroke:#1e88e5,stroke-width:2px,fill:none
    style D1 stroke:#43a047,stroke-width:2px,fill:none
    style D2 stroke:#43a047,stroke-width:2px,fill:none
    style D3 stroke:#43a047,stroke-width:2px,fill:none
```

### Workflow 3: Safe Deprovisioning

```mermaid
graph LR
    A["deprovision_user.sh alice"] --> B["Warning Display"]
    B --> C{Confirm?}
    C -->|No| D["Abort"]
    C -->|Yes| E["Create Backup"]
    E --> F["Lock Account"]
    F --> G["Kill Processes"]
    G --> H["Delete User"]
    H --> I["Deprovisioned"]
    
    style A stroke:#9c27b0,stroke-width:2px,fill:none
    style B stroke:#ffc107,stroke-width:2px,fill:none
    style I stroke:#43a047,stroke-width:2px,fill:none
    style D stroke:#f44336,stroke-width:2px,fill:none
```

---

## Monitoring & Observability

### Key Metrics

```
Metric                        Source          Query
─────────────────────────────────────────────────────
Users provisioned             Log file        grep "created successfully"
Users deprovisioned           Log file        grep "deprovisioned"
Average quota utilization     xfs_quota       "report -h"
Backups retained              Filesystem      ls -lh /var/backups/
Error rate                    Log file        grep "\[ERROR\]"
Operation latency             Log file        Parse timestamps
```

### Health Checks

```bash
# Check provisioning system health
./scripts/health_check.sh

Output:
  Quotas enabled
  Storage directory writable
  Log directory writable
  Puppet installed
  No pending backup deletions
  2 users over soft quota limit
```

---

## Scalability Considerations

### Current Scope

- Single VM deployment
- Manual user provisioning
- Local logging only
- Max ~1000 users (practical limit)

### Future Enhancements

| Enhancement | Benefit |
|-------------|---------|
| **Multi-VM deployment** | Scale across cluster |
| **REST API** | Programmatic access |
| **Grafana dashboards** | Real-time monitoring |
| **Prometheus metrics** | Time-series analytics |
| **LDAP integration** | Centralized identity |
| **Containerization** | Portable deployment |
| **Ansible wrapper** | Multi-OS support |

---

## Deployment Models

### Model 1: Standalone VM (Current)

```
Host → Rocky Linux VM (2 CPU, 4GB RAM, 40GB disk)
       ├── Puppet Agent
       ├── Storage provisioning scripts
       └── XFS quota system
```

**Pros:** Simple, easy to test, self-contained  
**Cons:** Single point of failure, limited scalability

### Model 2: Cluster Deployment (Future)

```
Host → Puppet Master
       ├─ Rocky Linux VM 1
       ├─ Rocky Linux VM 2
       └─ Rocky Linux VM 3
       
Storage Backend:
       ├─ NFS Server (for shared storage)
       └─ Backup Server (for archives)
```

**Pros:** High availability, distributed storage  
**Cons:** Complex management, network requirements

### Model 3: Containerized (Future)

```
Host → Podman/Docker Container
       ├── Rocky Linux base image
       ├── Puppet + scripts
       ├── Quota support
       └── Persistent volumes
```

**Pros:** Portable, ephemeral, easy to test  
**Cons:** Requires container orchestration

---

## Error Handling & Recovery

### Error Scenarios

| Error | Cause | Recovery |
|-------|-------|----------|
| "User already exists" | Duplicate provisioning | Deprovision + retry |
| "Quotas not enabled" | Filesystem not configured | Edit /etc/fstab + reboot |
| "Permission denied" | Not running with sudo | Re-run with `sudo` |
| "Backup failed" | Disk full | Free space + retry |
| "User locked in use" | Processes still running | `pkill -u username` + retry |

### Rollback Strategy

```
If provisioning fails:
  1. Check logs: tail /var/log/storage-provisioning/provisioning.log
  2. Restore VM snapshot: VirtualBox → Snapshots → Restore
  3. Or manual cleanup:
     - userdel -r username
     - xfs_quota remove limits
     - Investigate root cause
     - Retry with fixes
```

---

## Terminology & Concepts

### Core Technologies

#### XFS (X File System)
High-performance Linux filesystem used by Rocky Linux.  
- Supports project-based and user-based quotas natively.  
- Optimized for large files and concurrent I/O workloads.  
- Default filesystem for Rocky Linux and RHEL.  
- Tools: `xfs_quota`, `setquota`.

#### Puppet
Infrastructure-as-Code (IaC) automation framework for system configuration management.  
- Declarative and idempotent: applying the same manifest multiple times yields the same result.  
- Manifests describe desired system states (`init.pp`, `user.pp`).  
- Ensures consistent provisioning across multiple systems.

#### Bash
Standard Linux shell used for scripting direct provisioning and administrative tasks.  
- Executes core Linux utilities (`useradd`, `chmod`, `xfs_quota`).  
- Ideal for lightweight, ad-hoc, and test operations.  
- Integrates with Puppet for hybrid automation.

#### SSH (Secure Shell)
Encrypted protocol for secure remote access and file transfer (SFTP).  
- SSH Keys provide stronger authentication than passwords.  
- Chroot can restrict users to their home directories.  
- Configurable for per-user or per-group access.

#### Rocky Linux / RHEL
Enterprise-grade Linux distribution compatible with Red Hat Enterprise Linux (RHEL).  
- Stable, long-term support for enterprise environments.  
- Standardized tooling and predictable updates.  
- Default target OS for this project.

#### Sudo
Command-line utility that grants temporary root privileges.  
- Requires password confirmation for traceability.  
- All privileged provisioning operations use `sudo`.  
- Creates audit trail for administrative actions.

### Storage and Quota Concepts

| Concept | Description |
|----------|-------------|
| **Quota** | Disk space or inode limit assigned per user or group. Soft limits warn; hard limits enforce absolute ceilings. Prevents single users from exhausting shared storage. |
| **Inode** | Metadata structure storing file information (name, permissions, ownership, timestamps). Each file consumes one inode. Systems can run out of inodes even with free disk space. |
| **Filesystem** | Logical structure organizing files and directories. XFS supports quotas natively and scales efficiently for large datasets. Mount points attach filesystems to the Linux hierarchy. |
| **SELinux (Security-Enhanced Linux)** | Mandatory access control system extending beyond Unix permissions. Assigns security contexts to files and processes, enforcing policy-based restrictions. |

### User and Group Management

#### User Account
Unique system identity representing an individual or service.  
- Identified by a UID (user ID).  
- Associated with a shell, group memberships, and home directory.  
- Created with `useradd`; removed with `userdel -r`.  
- Default home: `/home/storage_users/{username}/`.

#### Group
Collection of users sharing common permissions.  
- Identified by a GID (group ID).  
- Example: `storage_users` group for all provisioned accounts.  
- Simplifies access control by managing permissions at group level.

#### Home Directory
Primary directory for user files and configuration.  
- Located under `/home/storage_users/{username}/`.  
- Owned by the user with mode `700` (owner-only access).  
- Contains subdirectories: `data/`, `backups/`, `temp/`, `logs/`.

#### PAM (Pluggable Authentication Modules)
Linux subsystem for authentication and session management.  
- Controls password verification, lockouts, and session policies.  
- Can enforce password expiration or login restrictions.

### Access Control and Security

| Term | Purpose |
|------|----------|
| **Authentication** | Verifies user identity. Uses passwords (temporary), SSH keys (cryptographic), or Puppet certificates. |
| **Authorization** | Determines permitted actions after authentication. Admins can provision and deprovision; users can only manage their own files. |
| **Chroot** | Restricts a user’s visible filesystem to a specific directory, e.g., `/home/storage_users/{username}/`. Common for SFTP-only access. |
| **SSH Key** | Public/private key pair for secure authentication. The public key is stored in `.ssh/authorized_keys`; the private key remains on the client. |

### Automation and Operations

#### Idempotent
Property where running an operation multiple times produces the same outcome as running it once.  
- Puppet manifests are idempotent by design.  
- Ensures safe, repeatable automation.

#### Provisioning
Creating and configuring new resources such as user accounts, directories, quotas, and permissions in one operation.  
- Implemented via `provision_user.sh` and Puppet manifests.  
- Validates inputs, creates user, applies quotas, and configures access.

#### Deprovisioning
Clean removal of user resources with audit and backup.  
- Archives user data before deletion.  
- Locks account, removes quotas, deletes directory.  
- Retains backup and metadata for compliance tracking.

#### Audit Trail
Comprehensive record of provisioning, deprovisioning, and system events.  
- Stored in `/var/log/storage-provisioning/provisioning.log`.  
- Includes timestamps, severity levels, and operation status.  
- Integrates with syslog or ELK for centralized analysis.

#### Cron Job
Scheduled task for recurring automation.  
- Examples: daily quota reports, cleanup scripts, or backup retention enforcement.  
- Configured via system `crontab` or under `/etc/cron.*`.

#### Manifest (Puppet)
Puppet configuration file (`.pp`) defining desired system state.  
- Written in Puppet’s Ruby-based DSL.  
- Applied via `puppet apply <manifest>` to enforce configuration.  

### Monitoring and Logging

| Term | Description |
|------|--------------|
| **Log File** | Text-based record of events with timestamps and severity levels (`INFO`, `ERROR`, `WARNING`). Primary log: `/var/log/storage-provisioning/provisioning.log`. |
| **Repquota** | Command-line utility for reporting disk quota usage. Displays usage, limits, and grace periods. |
| **Syslog / Journald** | Centralized Linux logging systems. Syslog is traditional; Journald is systemd-based. Can receive logs from provisioning scripts. |
| **Metrics** | Quantitative indicators for monitoring system health. Examples: users provisioned, quota utilization, error rate, and operation latency. |

### Backup and Recovery

#### Backup
Compressed copy (`.tar.gz`) of a user’s data for disaster recovery.  
- Created automatically during deprovisioning.  
- Includes metadata file with timestamp, username, and size.  
- Stored under `/var/backups/deprovisioned_users/`.

#### Snapshot
Point-in-time filesystem copy.  
- Faster restore but stored on the same system (not durable if disk fails).  
- Future support planned for snapshot-capable systems (e.g., Btrfs, Ceph).

#### Retention Policy
Defines how long backups are preserved before deletion.  
- Default: 30 days for deprovisioned user backups.  
- Balances compliance requirements and storage efficiency.