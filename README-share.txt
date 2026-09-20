RHCSA Docker Lab Environment

This is a complete, self-contained RHCSA lab environment that runs in Docker!
It provides 4 machines: workstation, servera, serverb, and bastion.

REQUIREMENTS:
- A Linux host (Ubuntu 20.04/22.04 recommended)
- Root/Sudo access
- Docker & Docker Compose v2 installed

HOW TO INSTALL & START:
1. Ensure Docker is installed on your Linux host.
2. (CRITICAL for Ubuntu/Debian) Configure Docker daemon for systemd:
   Run this on your host:
   sudo bash -c 'cat > /etc/docker/daemon.json << EOM
{
  "default-cgroupns-mode": "host",
  "exec-opts": ["native.cgroupdriver=systemd"],
  "storage-driver": "overlay2"
}
EOM'
   sudo systemctl restart docker

3. Run the host setup script to load required kernel modules:
   sudo ./scripts/host-setup.sh

4. Build and start the lab:
   ./lab.sh build
   ./lab.sh start

5. Initialize the lab (distributes SSH keys):
   ./lab.sh setup

HOW TO USE:
Connect to the workstation:
  ./lab.sh ssh workstation

From the workstation, you can run the custom grading tool:
  lab              # See all available practice scenarios
  lab start users  # Start the users scenario
  lab grade users  # Check your work
