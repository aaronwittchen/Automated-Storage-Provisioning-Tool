# **Automated Storage Provisioning Tool**

### **Overview**

The **Automated Storage Provisioning Tool** automates the process of creating, configuring, and managing storage users and their associated resources. It provisions new users, creates directories, assigns disk quotas, and manages access control using **Puppet** for configuration management on a **Rocky Linux** virtualized environment.

This project is ideal for environments where **multiple users or departments require managed storage space** with consistent configurations, quotas, and automated cleanup.

---

## **1. Why Rocky Linux**

Rocky Linux was chosen because it is **enterprise-grade, RHEL-compatible**, and offers a **stable, predictable environment** for infrastructure automation tools like Puppet and Ansible.

**Key Benefits:**

* **Binary compatibility** with Red Hat Enterprise Linux (RHEL)
* **Stable and secure** — ideal for long-term deployment
* **Excellent ecosystem support** for Puppet, Ansible, and system utilities
* **Lightweight** enough for testing in virtual machines
* Access to **enterprise-class package repositories**

---

## **2. Architecture Overview**

### **System Components**

| Component               | Description                                                              |
| ----------------------- | ------------------------------------------------------------------------ |
| **VM Host Machine**     | Your local workstation or server hosting the Rocky Linux VM.             |
| **Rocky Linux VM**      | The environment where Puppet and provisioning scripts run.               |
| **Puppet**              | Configuration management tool used to automate provisioning and cleanup. |
| **Shell Scripts**       | Supplementary tools for user management, quotas, and cleanup.            |
| **Storage Directories** | User or group directories with controlled quotas and permissions.        |

---

### **High-Level Workflow**

```
User Request → Provision Script/Puppet Manifest → 
1. Create User Account
2. Create Directory Structure
3. Set Ownership and Permissions
4. Apply Disk Quotas
5. Configure Access (SSH/SFTP)
6. Monitor Usage
7. Deprovision User When Needed
```

---

## **3. Virtual Machine Setup**

### **3.1 Hypervisor Options**

* **VirtualBox** (recommended for local testing)
* **VMware Workstation / Fusion**
* **KVM / libvirt** (for Linux environments)

### **3.2 VM Configuration**

| Resource    | Recommendation                                 | Notes                                 |
| ----------- | ---------------------------------------------- | ------------------------------------- |
| **CPU**     | 2 cores                                        | Adequate for Puppet and quota testing |
| **Memory**  | 4 GB                                           | More if testing multiple users        |
| **Disk**    | 20–40 GB                                       | Enough to create and test quotas      |
| **Network** | NAT (simpler) or Bridged (for external access) | NAT sufficient for testing            |


make sure in vm
Enable network and SSH access:

   ```bash
   sudo systemctl enable --now sshd
   ```
Update system:

   ```bash
   sudo dnf update -y
   ```

---

## **4. Environment Setup**

### **4.1 Tools Installation**

Install required packages:

```bash
sudo dnf install -y puppet quota xfsprogs openssh-server vim git
```

Enable and verify quota support:

```bash
sudo systemctl enable --now quotaon
sudo quotaon -av
```

### **4.2 Enable Quotas on Filesystem**

Edit `/etc/fstab`:

```
/dev/sda1 / xfs defaults,uquota 0 0
```

Then remount and initialize quotas:

```bash
sudo mount -o remount /
sudo quotacheck -cum /
sudo quotaon /
```

---

## **5. Core Components**

### **A. User Provisioning**

#### **Manual Approach**

```bash
sudo useradd -m -s /bin/bash storageuser01
sudo passwd storageuser01
sudo usermod -aG storagegroup storageuser01
```

#### **Script Example: `create_user.sh`**

```bash
#!/bin/bash
USER=$1
GROUP=storageusers
DIR="/storage/$USER"

# Create group if not exists
getent group $GROUP >/dev/null || groupadd $GROUP

# Create user
useradd -m -d $DIR -s /bin/bash -g $GROUP $USER
echo "User $USER created with directory $DIR"

# Set permissions
mkdir -p $DIR
chown $USER:$GROUP $DIR
chmod 700 $DIR

# Set quota (example: 2GB soft, 2.5GB hard)
setquota -u $USER 2000000 2500000 0 0 /
```

Make executable:

```bash
chmod +x create_user.sh
```

---

### **B. Directory and Permission Management**

Each user gets a **dedicated storage directory** (e.g., `/storage/<username>`).

**Shared Directories:**

```bash
mkdir /storage/shared
chown root:storageusers /storage/shared
chmod 770 /storage/shared
```

---

### **C. Quota Management**

Enable and monitor quotas:

```bash
sudo repquota -a
sudo edquota -u storageuser01
```

Example automated quota enforcement (in Puppet manifest):

```puppet
exec { 'set_user_quota':
  command => 'setquota -u storageuser01 2000000 2500000 0 0 /',
  unless  => 'quota -u storageuser01 | grep "2000000"',
}
```

---

### **D. Access Configuration**

**SSH/SFTP Access:**

* Users can log in via SSH or SFTP.
* Optionally restrict SFTP users:

  ```bash
  Match Group storageusers
      ChrootDirectory /storage/%u
      ForceCommand internal-sftp
  ```

**Optional Services:**

* **Samba** for Windows shares (`dnf install samba samba-client`)
* **NFS** for UNIX network storage

---

### **E. Deprovisioning**

**Manual Cleanup Example:**

```bash
#!/bin/bash
USER=$1
DIR="/storage/$USER"

setquota -u $USER 0 0 0 0 /
userdel -r $USER
rm -rf $DIR
echo "User $USER and directory $DIR removed."
```

**Puppet Manifest Snippet:**

```puppet
user { 'storageuser01':
  ensure => absent,
  managehome => true,
}
```

---

## **6. Automation with Puppet**

### **6.2 Example Manifest (`init.pp`)**

```puppet
class storage_provisioning {
  include storage_provisioning::users
  include storage_provisioning::directories
  include storage_provisioning::quotas
}
```

Apply the manifest:

```bash
sudo puppet apply /etc/puppetlabs/code/environments/production/manifests/site.pp
```

---

## **7. Testing**

**Functional Tests:**

1. Create multiple users and verify directory creation.
2. Check correct ownership and permissions.
3. Simulate quota limits using `dd`:

   ```bash
   dd if=/dev/zero of=/storage/user1/testfile bs=1M count=3000
   ```
4. Verify access via SSH/SFTP.
5. Run deprovisioning script and confirm cleanup.

**Validation:**

```bash
getent passwd | grep storage
repquota -a
ls -ld /storage/*
```

---

## **8. Monitoring & Maintenance**

* Use `quota -u <user>` for usage reports.
* Automate periodic reports with cron:

  ```bash
  (crontab -l ; echo "0 0 * * * repquota -a > /var/log/daily_quota_report.txt") | crontab -
  ```
* Integrate with email alerts for quota exceedances (optional).

---

## **10. Optional Enhancements**

* Integrate **Ansible** as an alternative automation layer.
* Use **LDAP** for centralized user management.
* Implement **Grafana + Prometheus** for quota and usage monitoring.
* Extend tool for **multi-volume storage provisioning**.
* Containerize the provisioning process using **Podman or Docker**.

---

## **11. Architecture Diagram**

```
+---------------------------+
|   User Request (CLI/API)  |
+------------+--------------+
             |
             v
+------------+-------------+
|   Puppet / Bash Scripts  |
|  (Provisioning Engine)   |
+------------+-------------+
             |
             v
+------------+-------------+
|  Rocky Linux VM          |
|  - User Accounts         |
|  - Directories & Quotas  |
|  - Access Configurations |
+------------+-------------+
             |
             v
+---------------------------+
|  Deprovision / Monitoring |
+---------------------------+
```

---

### **Summary**