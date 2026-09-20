# RHCSA Lab Environment in Docker

This project provides a fully containerized practice environment for the Red Hat Certified System Administrator (RHCSA) exam (RH124 & RH134). It uses Rocky Linux 9 and perfectly mimics the official Red Hat classroom setup with 4 machines:

* `bastion` (172.25.250.254) - Gateway, DNS, NFS, and Content Server
* `workstation` (172.25.250.9) - Student primary workstation
* `servera` (172.25.250.10) - Managed Server A
* `serverb` (172.25.250.11) - Managed Server B

## Features
- **Systemd Enabled**: Real systemd running as PID 1 inside the containers.
- **Custom Grading Engine**: Includes a custom `lab` CLI tool on the workstation to start, grade, and finish 12 core RHCSA topics (LVM, NFS, Users, Firewalld, etc.).
- **Virtual Disks**: Pre-configured virtual block devices (`/dev/vdb`) on servers for partitioning and LVM practice.
- **SSH Ready**: Automated distribution of SSH keys across all containers.

---

## 🛠️ Prerequisites

You must run this on a **Linux host** (Ubuntu 22.04/24.04 recommended) with Root/Sudo access.
*Docker on Windows/Mac cannot run systemd inside containers reliably due to cgroup limitations.*

1. Install **Docker** and **Docker Compose v2**.
2. **Configure Docker Daemon (CRITICAL for Ubuntu/Debian):**
   Systemd requires the container to have host cgroup namespaces. Run the following on your Linux host:
   ```bash
   sudo bash -c 'cat > /etc/docker/daemon.json << EOF
   {
     "default-cgroupns-mode": "host",
     "exec-opts": ["native.cgroupdriver=systemd"],
     "storage-driver": "overlay2"
   }
   EOF'
   sudo systemctl restart docker
   ```

---

## 🚀 Quick Start (Pull from Docker Hub)

To save time, you can pull the pre-built images directly from Docker Hub rather than building them from scratch.

**1. Clone the repository:**
```bash
git clone https://github.com/SouravDasHriday/rhcsa_lab_setup.git
cd rhcsa_lab_setup
```

**2. Setup Host Environment:**
Load the necessary kernel modules on your host (required for LVM/networking):
```bash
sudo ./scripts/host-setup.sh
```

**3. Configure your Docker Hub Username:**
Open `.env` and set `DOCKER_USER` to the username hosting the images:
```bash
echo "DOCKER_USER=souravdasdocker" > .env
```

**4. Pull and Start the Lab:**
```bash
docker compose pull
docker compose up -d
```

**5. Initialize the Lab:**
Run the setup script to distribute the SSH keys between the containers:
```bash
./lab.sh setup
```

---

## 💻 How to Practice

1. Connect to your `workstation`:
   ```bash
   ./lab.sh ssh workstation
   ```

2. Check available lab scenarios:
   ```bash
   [student@workstation ~]$ lab
   ```

3. Start a lab (e.g., `users`):
   ```bash
   [student@workstation ~]$ lab start users
   ```
   *Follow the printed instructions to complete the scenario.*

4. Grade your work:
   ```bash
   [student@workstation ~]$ lab grade users
   ```

5. Clean up the environment when finished:
   ```bash
   [student@workstation ~]$ lab finish users
   ```

---

## 🏗️ Building from Source (Optional)

If you want to modify the Dockerfiles or build the images yourself:
```bash
# 1. Build the images (takes ~5-10 mins)
./lab.sh build

# 2. Start the lab
./lab.sh start

# 3. Initialize
./lab.sh setup
```

## 🧹 Resetting the Environment

If you completely break your servers (e.g., corrupt `/etc/fstab` or destroy the virtual disks), you can factory reset the entire environment:
```bash
# Run this on your host machine
./lab.sh reset
```
*Warning: This destroys all data and rebuilds the lab from scratch!*
