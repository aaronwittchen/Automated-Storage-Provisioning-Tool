### **9. Check Logs**
```bash
# View provisioning logs
sudo tail -f /var/log/storage-provisioning/provisioning.log

# Or view entire log
sudo less /var/log/storage-provisioning/provisioning.log
```

## 📋 Quick Test Checklist

```bash
# Complete test sequence
cd ~/storage-provisioning/scripts

# 1. Provision
sudo ./provision_user.sh alice -q 10G
# Note the password

# 2. Verify
id alice
ls -la /home/storage_users/alice
sudo xfs_quota -x -c "report -h" /

# 3. Create test data
sudo -u alice bash -c 'echo "Hello" > /home/storage_users/alice/data/file.txt'

# 4. Deprovision with backup
sudo ./deprovision_user.sh alice --backup
# Type 'yes'

# 5. Verify cleanup
id alice  # Should fail
ls /var/backups/deprovisioned_users/  # Should see backup
```


---

### **Step 10: Testing Workflow**

**Create test script (`tests/test_provisioning.sh`):**

```bash
#!/bin/bash

echo "=== Storage Provisioning Test Suite ==="

# Test 1: Create user
echo "Test 1: Creating test user..."
ssh storage-vm 'bash ~/storage-provisioning/scripts/provision_user.sh testuser001 5G'

# Test 2: Verify user exists
echo "Test 2: Verifying user..."
ssh storage-vm 'id testuser001'

# Test 3: Check directory
echo "Test 3: Checking directory..."
ssh storage-vm 'ls -la /home/storage_users/testuser001'

# Test 4: Check quota
echo "Test 4: Checking quota..."
ssh storage-vm 'sudo xfs_quota -x -c "report -h" / | grep testuser001'

# Test 5: Test SFTP access
echo "Test 5: Testing SFTP access..."
# (Would need to set up keys for this)

# Test 6: Deprovision
echo "Test 6: Deprovisioning user..."
ssh storage-vm 'echo "yes" | bash ~/storage-provisioning/scripts/deprovision_user.sh testuser001'

# Test 7: Verify removal
echo "Test 7: Verifying removal..."
ssh storage-vm 'id testuser001' && echo "FAIL: User still exists" || echo "PASS: User removed"

echo "=== Tests Complete ==="
```

Make it executable:
```bash
chmod +x tests/test_provisioning.sh
```

---

## **Phase 4: Development Cycle**

### **Step 11: Iterative Development Loop**

1. **Write/modify scripts or manifests on host**
   ```bash
   vim scripts/provision_user.sh
   ```

2. **Validate syntax locally (before pushing)**
   ```bash
   # For bash scripts
   bash -n scripts/provision_user.sh
   shellcheck scripts/provision_user.sh  # if you have shellcheck installed
   
   # For Puppet
   puppet parser validate manifests/user.pp
   ```

3. **Sync to VM**
   ```bash
   ./sync.sh
   # or
   sync-vm
   ```

4. **SSH into VM and test**
   ```bash
   ssh storage-vm
   cd ~/storage-provisioning
   
   # Test scripts
   bash scripts/provision_user.sh testuser001 5G
   
   # Or test Puppet with --noop (dry-run)
   sudo puppet apply --noop manifests/init.pp
   
   # Then apply for real
   sudo puppet apply manifests/init.pp
   ```

5. **Verify results**
   ```bash
   # Check user
   id testuser001
   
   # Check directory
   ls -la /home/storage_users/testuser001
   
   # Check quota
   sudo xfs_quota -x -c 'report -h' / | grep testuser001
   ```

6. **Document findings**
   ```bash
   # On host machine
   vim docs/testing.md
   # Record what worked, what didn't, any errors
   ```

7. **Commit changes**
   ```bash
   git add .
   git commit -m "feat: add user provisioning with quota support"
   ```

8. **If something breaks: restore VM snapshot**
   ```bash
   # In VirtualBox/VMware: Restore to previous snapshot
   # Then retry with fixes
   ```

---

## **Phase 5: Enhancements & Documentation**

### **Step 12: Add Logging System**

Create log directory on VM:
```bash
ssh storage-vm 'sudo mkdir -p /var/log/storage-provisioning && sudo chmod 755 /var/log/storage-provisioning'
```

Update all scripts to use logging (already included in utils.sh above)

---

### **Step 13: Create Comprehensive Documentation**

**`README.md`:**
```markdown
# Automated Storage Provisioning Tool

Enterprise-grade storage user provisioning system for Rocky Linux.

## Features
- Automated user creation with quotas
- Directory structure management
- SFTP access configuration
- Safe deprovisioning with confirmations
- Comprehensive logging

## Quick Start
[Installation and usage instructions]

## Architecture
[Link to architecture.md]

## Testing
[Link to testing.md]
```

**`docs/architecture.md`:** Draw system diagram, explain components

**`docs/usage.md`:** Step-by-step usage examples

**`docs/testing.md`:** Test cases and results

---

### **Step 14: Optional Enhancements**

1. **Add monitoring:**
   ```bash
   # Script to check disk usage
   scripts/monitor_usage.sh
   ```

2. **Email notifications:**
   - When quota is 80% full
   - When provisioning succeeds/fails

3. **Web interface:**
   - Simple Flask/Django app to provision users
   - Deployed on the VM

4. **Multi-server support:**
   - Extend to provision across multiple VMs

---

## **Quick Reference Commands**

```bash
# On host
cd ~/projects/storage-provisioning
./sync.sh
ssh storage-vm

# On VM
cd ~/storage-provisioning
bash scripts/provision_user.sh alice 10G
sudo puppet apply manifests/init.pp
sudo xfs_quota -x -c 'report -h' /
bash scripts/deprovision_user.sh alice
```



Step	How it happens in the real world
1. Write code	Developers write scripts or code locally or in an IDE.
2. Validate locally	They run automated linters, unit tests, or local validations.
3. Sync / Deploy to test environment	Instead of manually using rsync or scp, companies often use CI/CD pipelines: Jenkins, GitLab CI, GitHub Actions, etc., to push code automatically to test servers.
4. Commit / Version control	Code is committed to Git repositories, with code reviews and pull requests.
5. Apply scripts / Run tests	The VM/test server runs automated integration tests, configuration scripts, or provisioning scripts. Containers or orchestration tools may be used.
6. Test / QA	QA engineers or automated tests verify everything works: users created, quotas set, logs written.
7. Verify & deploy	If tests pass, code may go to staging and then production servers. Monitoring tools watch for failures.