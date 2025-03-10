# Ubuntu Security Setup

## Description
Ubuntu Security Setup is a collection of scripts designed to enhance the security of Ubuntu-based systems. It automates essential security configurations to protect against common threats and vulnerabilities.

## Features
- Firewall configuration using `ufw`
- Automatic security updates
- Intrusion detection system setup
- Secure SSH configuration
- Hardening system settings

##  **Functionality**  
The script performs the following operations:  

### **1. System Update**  
- Full package and distribution upgrade  
- Removal of unused packages and cache cleanup  

### **2. User Management**  
- Creation of a new user with sudo privileges  
- Configuration of SSH key authentication  
- Restriction of root user access  

### **3. SSH Configuration**  
- Changing the default SSH port  
- Disabling password login  
- Preventing root user access  
- Configuring additional SSH security parameters  
- Creating a warning SSH banner  

### **4. Firewall Configuration (UFW)**  
- Setting basic rules (blocking incoming traffic)  
- Configuring permissions for SSH and other selected services  
- Allowing the definition of additional ports  

### **5. Protection Against Brute Force Attacks (fail2ban)**  
- Installing and configuring fail2ban  
- Creating rules to protect SSH  
- Configuring protection against port scanning  
- Setting up security rules for web servers (optional)  

### **6. Automatic Updates**  
- Installing and configuring unattended-upgrades  
- Configuring automatic package cleanup  
- Setting automatic reboots at a specific time  

### **7. Logging (rsyslog)**  
- Configuring the logging system  
- Setting up log rotation  
- Configuring informative log messages  

### **8. Installation of System Utilities**  
- Diagnostic tools (htop, iotop, iftop)  
- Networking tools (net-tools, curl, wget, nmap, tcpdump)  
- Security tools (lynis, rkhunter, chkrootkit)  

### **9. Advanced Security Measures**  
- Configuring kernel parameters to enhance network security  
- Restricting access to critical files  
- Enforcing password policies  
- Configuring the auditing system (auditd)  
- Configuring AppArmor  
- Rootkit detection  

### **10. Security Audit**  
- Running Lynis to assess security levels  
- Running rootkit checks  
- Generating a security settings report
## Installation
1. Clone the repository:
   ```sh
   git clone https://github.com/kukoboris/ubuntu-security-setup.git
   cd ubuntu-security-setup
   ```
2. Run the setup script:
   ```sh
   chmod +x ubuntu-security-setup.sh
   ./ubuntu-security-setup.sh
   ```

## Requirements
- Ubuntu 20.04 or later
- sudo privileges

## Usage
After installation, the system will have improved security settings. You can manually adjust configurations in the script files according to your needs.

## Contribution
Contributions are welcome! Feel free to submit pull requests or open issues to improve this project.

## License
This project is licensed under the MIT License. See the [LICENSE](../LICENSE) file for details.

