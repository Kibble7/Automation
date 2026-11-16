# Manage Linux Servers with Ansible

An Ubuntu server is used as the **Ansible controller**. It manages other Ubuntu/Linux servers (managed nodes) over SSH.

```
Ubuntu Server - Ansible Controller
(Ansible installed here, SSH key management, playbooks)
        |
        |  SSH - Port 22
        |
+-------+----------+----------+
|                  |          |
Ubuntu 01        Ubuntu 02   Ubuntu 03
Managed node     Managed node  Managed node
```

> **Note:** All IP addresses in this document are examples. Replace `<SERVER01_IP>` and `<SERVER02_IP>` with the IPs of your own servers.

---

## 1. Install Ansible on the Ubuntu server

```bash
# install Ansible on ubuntu server
sudo apt update
sudo apt install python3-pip pipenv openssh-client -y
```

```bash
# check version
pipenv --version
python3 --version
```

```bash
# create ansible project folder
mkdir ~/ansible-project
cd ~/ansible-project
```

```bash
# create virtual environment
pipenv shell

# install Ansible
pipenv install ansible

# verify
ansible --version
```

---

## 2. Configure SSH on remote machines

On each Ubuntu/Linux machine you want Ansible to manage:

```bash
sudo apt update
sudo apt install openssh-server python3 -y
```

Enable SSH:

```bash
sudo systemctl enable --now ssh
```

Check:

```bash
sudo systemctl status ssh
```

Find the machine's IP:

```bash
hostname -I
```

For example:

| Machine | IP address | Role |
|---|---|---|
| Ubuntu-Ansible | 192.168.1.100 | Controller |
| Ubuntu-Server01 | 192.168.1.101 | Managed node |
| Ubuntu-Server02 | 192.168.1.102 | Managed node |

Replace these example IPs with yours.

---

## 3. Set up SSH key authentication

Go back to your Ansible controller.

Generate an SSH key:

```bash
ssh-keygen -t ed25519
```

```bash
# create ssh key name ansible
ssh-keygen -t ed25519 -f ~/.ssh/ansible
```

Copy the key to your first remote machine:

```bash
ssh-copy-id username@192.168.1.101
```

```bash
# copy public key to another server
ssh-copy-id -i ~/.ssh/ansible.pub administrator@<SERVER01_IP>
ssh-copy-id -i ~/.ssh/ansible.pub administrator@<SERVER02_IP>
```

And your second:

```bash
ssh-copy-id username@192.168.1.102
```

```bash
# check ssh key
ls -al ~/.ssh
```

Test:

```bash
ssh username@192.168.1.101
```

If you can connect without entering your SSH password, your key authentication is working.

```bash
# test key authentication
ssh -i ~/.ssh/ansible administrator@<SERVER01_IP>
```

```bash
# if key is asking password
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

---

## 4. Create Ansible inventory

On your controller, inside ansible-project:

```bash
nano inventory.ini
```

Add:

```ini
[linux_servers]
server01 ansible_host=<SERVER01_IP>
server02 ansible_host=<SERVER02_IP>

[linux_servers:vars]
ansible_user=administrator
ansible_ssh_private_key_file=/home/administrator/.ssh/ansible
ansible_ssh_common_args=-o IdentitiesOnly=yes
```

Replace `username` with the account used on your remote machines.

---

## 5. Test Ansible over SSH

Make sure you are inside the Pipenv environment.

```bash
pipenv shell
```

Run:

```bash
ansible linux_servers -i inventory.ini -m ping
```

Expected result:

```
server01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
server02 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

---

## 6. Send a maintenance message

Create a playbook:

```bash
nano maintenance.yml
```

Add:

```yaml
---
- name: Send maintenance notification
  hosts: linux_servers
  become: true

  tasks:
    - name: Notify logged-in users
      ansible.builtin.command:
        argv:
          - wall
          - "SERVER UPDATE IN PROGRESS - Please save your work. Maintenance will begin shortly."
      changed_when: false
```

Execute:

```bash
ansible-playbook -i inventory.ini maintenance.yml
```

```bash
ansible-playbook -i inventory.ini maintenance.yml --ask-become-pass
```

```bash
ansible-playbook -i inventory.ini maintenance.yml -K
```

```bash
ansible server01 -i inventory.ini -m command -a "wall Test notification from Ansible" -b -K
```

```bash
ansible server01 -i inventory.ini -m command -a "wall 'Test notification from Ansible'" -b -K
```

```bash
ansible server01 -i inventory.ini -m command -a "wall 'SERVER UPDATE IN PROGRESS - Please save your work.'" -b -K
```

---

## 7. Your final architecture

```
Ubuntu Ansible Controller
  Pipenv environment
  Python + Ansible + SSH private key
        |
        |  SSH / Port 22
        |
   +----+-----------------+
Server 01              Server 02
SSH + Python 3         SSH + Python 3
Managed                Managed
```

One useful tip: You don't need to enter `pipenv shell` every time. You can run Ansible directly using:

```bash
pipenv run ansible linux_servers -i inventory.ini -m ping
```

---

# Part 2 - Using a `hosts` file and `ansible.cfg`

This is the setup used for day-to-day maintenance, so you don't need `-i inventory.ini` on every command.

## Hosts file

```bash
cd ~/ansible
nano hosts
```

Add:

```ini
[vms]
server01 ansible_host=<SERVER01_IP>
server02 ansible_host=<SERVER02_IP>

[vms:vars]
ansible_user=administrator
ansible_ssh_private_key_file=/home/administrator/.ssh/ansible
ansible_connection=ssh
```

## ansible.cfg

```bash
nano ansible.cfg
```

```ini
[defaults]
inventory = ./hosts
host_key_checking = False
interpreter_python = auto_silent
timeout = 15

[ssh_connection]
pipelining = True
```

## Commands

```bash
# command
ansible-inventory --list
```

```bash
# check ping
ansible vms -i hosts -m ping
ansible vms -m ping
```

```bash
ansible vms -m shell -a 'echo "<server will be in maintenance today>" | wall' -b -K
```

```bash
# If you want to schedule a shutdown in 15 minutes
ansible vms -m shell -a 'shutdown -h +15 "Server maintenance starting"' -b -K
```

```bash
# broadcast message
ansible vms -m shell -a 'echo "WARNING: Server maintenance will begin in 15 minutes. Please save your work and log out." | wall' -b -K
```

```bash
# shutdown both server
ansible vms -m shell -a 'shutdown -h now' -b -K
```

```powershell
# start server (run in PowerShell on the Hyper-V host)
Start-VM -Name "server01"
Start-VM -Name "server02"
```

```bash
# verify server
ansible vms -m ping
```

## Create maintenance message playbook

```bash
cd ~/ansible
nano message.yml
```

```yaml
---
- name: Linux Server Maintenance Announcement
  hosts: vms
  become: true
  gather_facts: true

  vars:
    maintenance_message: |
      ==========================================
      SERVER MAINTENANCE ANNOUNCEMENT
      ==========================================
      Server: {{ inventory_hostname }}
      Maintenance Date: Today
      Please save your work and log out.
      Thank you.
      ==========================================

  tasks:
    - name: Display maintenance announcement
      ansible.builtin.command:
        argv:
          - wall
          - "{{ maintenance_message }}"
```

Run it:

```bash
ansible-playbook message.yml -K
```

## Send a message to a terminal

```bash
# server 1 this is work
ansible server01 -m shell -a 'echo "MAINTENANCE: Please save your work." > /dev/pts/0' -b -K

ansible vms -m shell -a 'echo "MAINTENANCE: Please save your work." > /dev/pts/0' -b -K
```

```bash
ansible vms -m shell -a 'echo "<enter system message>" | wall' -b -K
```

---

## Notes

* `-b` runs the command with sudo (become) and `-K` asks for the sudo password.
* `ansible_host` IPs in `hosts` / `inventory.ini` are placeholders. Use your own, and do not commit real IPs to a public repo.
