# Network Configuration: NAT vs Bridged Adapter

## NAT (Network Address Translation)

### Overview

Your VM shares your host machine's internet connection and hides behind your host's IP address, similar to a computer behind a router on a home network. The host acts as a gateway, performing NAT between the VM and the outside network.

### Key Characteristics

| Feature | Description |
|---------|-------------|
| **Visibility** | VM is not visible to other devices on your LAN. Only your host can access it directly. |
| **IP Address** | VM receives a private IP (e.g., 10.0.2.15) managed internally by VirtualBox or VMware. |
| **Internet Access** | VM can access the internet, but other devices cannot access the VM directly. |
| **Use Case** | Safe and simple for local testing, development, or downloading packages. |
| **Port Forwarding** | Required if you need to access VM services (SSH, web server, etc.) from your host. |

### Example Configuration

Host IP: `192.168.1.100`
VM IP (NAT): `10.0.2.15`

To SSH from host to VM, you must configure port forwarding (e.g., HostPort 2222 → GuestPort 22):

```bash
ssh -p 2222 user@127.0.0.1
```

### Advantages

- Works immediately without additional configuration
- Good isolation and security
- Internet access functions automatically

### Disadvantages

- Not reachable from other devices on your LAN
- Requires manual port forwarding for SSH or web access

---

## Bridged Adapter

### Overview

The VM connects directly to your physical network as if it were another real computer on your LAN. The VM receives an IP address from your network's DHCP server in the same subnet as your host.

### Key Characteristics

| Feature | Description |
|---------|-------------|
| **Visibility** | VM is visible on the network like any other machine. |
| **IP Address** | VM receives a LAN IP address (e.g., 192.168.1.105). |
| **Internet Access** | Works through your router, identical to your host. |
| **Use Case** | Ideal when you need to SSH or access the VM from other machines on the network. |
| **Port Forwarding** | Not needed. You connect directly using the VM's IP address. |

### Example Configuration

Host IP: `192.168.1.100`
VM IP (Bridged): `192.168.1.105`

SSH from host to VM:

```bash
ssh user@192.168.1.105
```

### Advantages

- Full network visibility as a real machine
- Easy SSH or access from any device on your LAN
- No port forwarding required

### Disadvantages

- Requires additional setup (firewall and router DHCP configuration)
- Lower isolation. VM is exposed on the same network
- May conflict with VPNs or Wi-Fi networks, especially on laptops

---

## Comparison

| Feature | NAT | Bridged Adapter |
|---------|-----|-----------------|
| VM visible on LAN | No | Yes |
| Internet access | Yes | Yes |
| SSH from host | Requires port forwarding | Direct connection |
| Network isolation | High | Low |
| Setup complexity | Easy | Moderate |
| Common use | Local development and testing | Server access and multi-device testing |

---

## Recommendation

For the Automated Storage Provisioning Tool with rsync file synchronization and SSH access from your host to the VM, **Bridged Adapter is the recommended choice**. This configuration allows you to use a real IP address like `192.168.68.105` without port forwarding overhead.