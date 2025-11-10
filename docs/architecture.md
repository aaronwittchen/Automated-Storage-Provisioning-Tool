# Architecture: Automated Storage Provisioning Tool

## Overview

The Automated Storage Provisioning Tool is a containerized, enterprise-grade system for managing user accounts, storage directories, disk quotas, and access controls on Rocky Linux. This document describes the system design, components, data flow, and deployment model.

**Target Environment:** Rocky Linux 8/9 virtual machines with XFS filesystems  
**Automation Framework:** Puppet + Bash scripts  
**Use Case:** Multi-user environments requiring consistent, auditable storage management

---

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
    
    Host -->|rsync/SCP| Deploy["Deploy"]
    
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

---

## Component Hierarchy

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
        Utils["Utilities<br/>Logging<br/>Validation"]
    end
    
    subgraph L3["Level 3: System Integration"]
        User_Tools["useradd/userdel/usermod"]
        Group_Tools["groupadd/groupmod"]
        Quota_Tools["xfs_quota/setquota"]
        File_Tools["mkdir/chown/chmod"]
        SSH_Tools["sshd/SSH keys"]
        Audit_Tools["auditd/syslog"]
    end
    
    subgraph L4["Level 4: Storage"]
        User_Home["/home/storage_users/{user}/"]
        System_Logs["/var/log/storage-provisioning/"]
        Backups["/var/backups/deprovisioned_users/"]
    end
    
    CLI --> Prov
    Puppet_UI --> Prov
    Batch --> Prov
    
    Prov --> Utils
    Deprov --> Utils
    
    Prov --> User_Tools
    Prov --> Quota_Tools
    Prov --> File_Tools
    Prov --> SSH_Tools
    Prov --> Audit_Tools
    
    Deprov --> User_Tools
    Deprov --> Quota_Tools
    Deprov --> Audit_Tools
    
    User_Tools --> L4
    Quota_Tools --> L4
    File_Tools --> L4
    Audit_Tools --> L4
    
    style L1 fill:#e3f2fd
    style L2 fill:#f3e5f5
    style L3 fill:#fff3e0
    style L4 fill:#e8f5e9
```

**User Provisioning Sequence Chart**

**User Deprovisioning Sequence Chart**

---

## Data Flow: Provisioning User

```mermaid
sequenceDiagram
    actor Admin
    participant Script as provision_user.sh
    participant System as Linux System
    participant FS as XFS Filesystem
    participant Log as Logs

    Admin->>Script: ./provision_user.sh alice -q 10G
    
    rect rgb(200, 220, 255)
    Note over Script: Validation Phase
    Script->>Script: Validate username format
    Script->>Script: Validate quota format
    Script->>System: Check if user exists
    end
    
    rect rgb(200, 255, 200)
    Note over Script: User Creation Phase
    Script->>System: useradd alice
    Script->>System: groupadd storage_users
    Script->>System: Generate temp password
    end
    
    rect rgb(255, 240, 200)
    Note over Script: Directory Setup Phase
    Script->>FS: mkdir /home/storage_users/alice
    Script->>FS: chown alice:storage_users
    Script->>FS: chmod 700
    Script->>FS: Create subdirs (data,backups,temp,logs)
    end
    
    rect rgb(255, 220, 220)
    Note over Script: Quota Enforcement Phase
    Script->>System: xfs_quota set 10G limit
    Script->>System: xfs_quota verify
    end
    
    rect rgb(220, 200, 255)
    Note over Script: Access Control Phase
    Script->>System: SSH access: DENY
    Script->>System: Add SELinux context
    Script->>System: Add audit rules
    end
    
    Script->>Log: [INFO] User provisioned successfully
    Script->>Admin: ✅ Success + Temp Password
```

---

## Data Flow: Deprovisioning User

```mermaid
sequenceDiagram
    actor Admin
    participant Script as deprovision_user.sh
    participant System as Linux System
    participant FS as XFS Filesystem
    participant Backup as Backup Storage
    participant Log as Logs

    Admin->>Script: ./deprovision_user.sh alice --backup
    
    rect rgb(255, 200, 200)
    Note over Script: Safety Phase
    Script->>System: Verify user exists
    Script->>Admin: ⚠️ Display warning
    Script->>Admin: Require 'yes' confirmation
    Admin->>Script: yes
    Script->>System: Gather user info (UID, disk usage)
    end
    
    rect rgb(255, 240, 200)
    Note over Script: Backup Phase
    Script->>FS: Read /home/storage_users/alice
    Script->>Backup: tar -czf alice_TIMESTAMP.tar.gz
    Script->>Backup: Create alice_TIMESTAMP.tar.gz.meta
    Script->>Log: [INFO] Backup created
    end
    
    rect rgb(200, 200, 255)
    Note over Script: Account Termination Phase
    Script->>System: passwd -l alice (lock account)
    Script->>System: pkill -u alice (kill processes)
    Script->>System: Remove cron jobs
    Script->>System: xfs_quota remove limits
    end
    
    rect rgb(255, 220, 220)
    Note over Script: Cleanup Phase
    Script->>System: userdel -r alice
    Script->>FS: rm -rf /home/storage_users/alice
    Script->>System: Remove SSH config
    Script->>System: Remove audit rules
    end
    
    Script->>Log: [INFO] User deprovisioned
    Script->>Admin: ✅ Deprovisioning complete<br/>Backup: /var/backups/.../alice_TIMESTAMP.tar.gz<br/>Restore command provided
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
    G --> H["✅ alice provisioned"]
    
    style A fill:#e1f5ff
    style H fill:#c8e6c9
    style B fill:#fff9c4
    style C fill:#ffe0b2
    style E fill:#f8bbd0
```

### Workflow 2: Batch Provisioning

```mermaid
graph TD
    A["Create users.txt<br/>alice<br/>bob<br/>charlie"] --> B["for each user in file"]
    B --> C["provision_user.sh"]
    C --> D1["✅ alice: 5GB quota"]
    C --> D2["✅ bob: 5GB quota"]
    C --> D3["✅ charlie: 5GB quota"]
    
    style A fill:#e1f5ff
    style D1 fill:#c8e6c9
    style D2 fill:#c8e6c9
    style D3 fill:#c8e6c9
```

### Workflow 3: Safe Deprovisioning

```mermaid
graph LR
    A["deprovision_user.sh alice"] --> B["⚠️ Warning Display"]
    B --> C{Confirm?}
    C -->|No| D["❌ Abort"]
    C -->|Yes| E["Create Backup"]
    E --> F["Lock Account"]
    F --> G["Kill Processes"]
    G --> H["Delete User"]
    H --> I["✅ Deprovisioned<br/>Backup saved: 30 days"]
    
    style A fill:#ffccbc
    style B fill:#fff9c4
    style I fill:#c8e6c9
    style D fill:#ffcdd2
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
  ✅ Quotas enabled
  ✅ Storage directory writable
  ✅ Log directory writable
  ✅ Puppet installed
  ✅ No pending backup deletions
  ⚠️  2 users over soft quota limit
```

---

## Scalability Considerations

### Current Scope

- Single VM deployment
- Manual user provisioning
- Local logging only
- Max ~1000 users (practical limit)

### Future Enhancements

| Enhancement | Benefit | Effort |
|-------------|---------|--------|
| **Multi-VM deployment** | Scale across cluster | Medium |
| **REST API** | Programmatic access | Medium |
| **Grafana dashboards** | Real-time monitoring | Low |
| **Prometheus metrics** | Time-series analytics | Medium |
| **LDAP integration** | Centralized identity | High |
| **Containerization** | Portable deployment | Medium |
| **Ansible wrapper** | Multi-OS support | High |

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

## File Organization Reference

```
automated-storage-provisioning/
│
├── README.md                          # Quick start guide
├── .gitignore                         # Git exclusions
│
├── docs/
│   ├── architecture.md                # This file
│   ├── usage.md                       # User manual
│   └── testing.md                     # Test procedures
│
├── scripts/
│   ├── provision_user.sh              # Provision entrypoint
│   ├── deprovision_user.sh            # Deprovision entrypoint
│   ├── set_quota.sh                   # Quota management
│   ├── utils.sh                       # Shared functions
│   └── health_check.sh                # System health
│
├── manifests/
│   ├── init.pp                        # Main orchestrator
│   ├── user.pp                        # User provisioning module
│   └── decommission.pp                # User removal module
│
├── templates/
│   └── README.txt.epp                 # User README template
│
├── examples/
│   └── site.pp                        # Example manifest
│
├── tests/
│   ├── test_provisioning.sh           # Integration tests
│   ├── test_quota.sh                  # Quota tests
│   └── fixtures/                      # Test data
│
└── logs/
    └── (auto-generated by VM)
```

---

## Change Log & Version Control

All changes tracked via Git commits with descriptive messages:

```
feat: Add user provisioning with quota support
fix: Correct XFS quota syntax for hard limits
docs: Update architecture with backup workflow
refactor: Extract validation logic to utils.sh
test: Add quota enforcement test cases
```

Commit early, commit often—use Git as your audit trail!

---

## Support & Troubleshooting

For issues, refer to:

1. **Logs:** `/var/log/storage-provisioning/provisioning.log`
2. **README:** Main project README with quick start
3. **This file:** Architecture details and design decisions
4. **GitHub Issues:** Community support and known issues