# mshauri-cli

> **mshauri-cli** is a Bash-powered system utility for automating local Linux server hardening and M-Pesa API diagnostics. *Mshauri* means "advisor" in Swahili — your trusted command-line advisor for server security and fintech API health.

---

## Features

- 🔒 **Server Hardening Checklist**
  - SSH configuration audit (PermitRootLogin, PasswordAuthentication, X11Forwarding, MaxAuthTries)
  - Firewall status check (UFW / firewalld)
  - Pending security updates detection (apt / yum)
  - Empty password user detection
  - Kernel sysctl security parameters validation

- 📡 **M-Pesa API Diagnostics**
  - DNS resolution check for `sandbox.safaricom.co.ke`
  - HTTP/HTTPS connectivity test
  - SSL/TLS certificate expiry check
  - OAuth 2.0 token generation test (with credentials)

- 📋 **Combined System Report**
  - System info (OS, kernel, CPU, memory, disk)
  - Open listening ports
  - Recent login history
  - M-Pesa endpoint status

- 📝 **Automatic logging** — every run writes a timestamped log to `/tmp/`

---

## Requirements

- Bash 4.0+
- `curl`, `openssl`, `host` or `nslookup` (for M-Pesa checks)
- `ss` or `netstat` (for report)
- `ufw` or `firewall-cmd` (for firewall checks)
- Linux (Debian/Ubuntu or RHEL/CentOS)

Install common dependencies on Ubuntu/Debian:
```bash
sudo apt-get install -y curl openssl dnsutils net-tools
```

---

## Installation

```bash
# Clone the repository
git clone https://github.com/youruser/mshauri-cli-20260623.git
cd mshauri-cli-20260623

# Make the script executable
chmod +x mshauri.sh

# Optional: install system-wide
sudo cp mshauri.sh /usr/local/bin/mshauri
```

---

## Usage

### Show help
```bash
./mshauri.sh help
```

### Run server hardening checklist
```bash
# As a regular user (partial checks)
./mshauri.sh harden

# As root (full checks including /etc/shadow)
sudo ./mshauri.sh harden
```

**Sample output:**
```
========== SERVER HARDENING CHECKLIST ==========

[INFO]  Checking SSH configuration...
[OK]    SSH: PermitRootLogin is disabled
[WARN]  SSH: Consider disabling PasswordAuthentication
[OK]    SSH: X11Forwarding is disabled
[INFO]  Checking firewall status...
[OK]    UFW firewall is active
[INFO]  Checking for pending security updates...
[WARN]  3 package(s) need updating. Run: sudo apt-get upgrade
```

### Run M-Pesa API diagnostics
```bash
# Basic connectivity (no credentials)
./mshauri.sh mpesa-check

# Full check including OAuth token test
./mshauri.sh mpesa-check \
  --consumer-key YOUR_CONSUMER_KEY \
  --consumer-secret YOUR_CONSUMER_SECRET

# With custom shortcode
./mshauri.sh mpesa-check \
  --consumer-key abc123 \
  --consumer-secret xyz789 \
  --shortcode 600000
```

**Sample output:**
```
========== M-PESA API DIAGNOSTICS ==========

[INFO]  Resolving sandbox.safaricom.co.ke...
[OK]    DNS resolution successful for sandbox.safaricom.co.ke
[INFO]  Testing M-Pesa sandbox reachability...
[OK]    Reached https://sandbox.safaricom.co.ke successfully
[INFO]  Checking TLS/SSL certificate for M-Pesa sandbox...
[OK]    SSL certificate valid until: Dec 31 23:59:59 2025 GMT
[INFO]  Fetching M-Pesa OAuth token...
[OK]    OAuth token obtained: eyJhbGciOiJSUzI1NiIs...
```

### Generate combined report
```bash
./mshauri.sh report
```
This creates a file like `mshauri_report_20260623_120000.txt` in the current directory.

### Show version
```bash
./mshauri.sh version
# mshauri-cli v1.0.0
```

---

## File Structure

```
mshauri-cli-20260623/
├── mshauri.sh        # Main script
├── README.md         # This file
└── .gitignore        # Git ignore rules
```

---

## Logs

All runs produce a timestamped log file:
```
/tmp/mshauri_20260623_120000.log
```

---

## Security Notes

- Never commit real M-Pesa credentials to version control.
- Use environment variables or a `.env` file (add it to `.gitignore`) for credentials.
- This tool is intended for use on servers you own and administer.

---

## License

MIT License

Copyright (c) 2026 mshauri-cli contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
