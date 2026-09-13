# AWS EC2 NAT Gateway



## Architecture


                         Internet
                            │
                    Internet Gateway
                            │
                    Public Subnet
                     10.0.1.0/24
                            │
                  ┌─────────▼─────────┐
                  │      gateway      │
                  │     EC2 / NAT     │
                  │                   │
                  │ Public: 10.0.1.131│
                  │ Private:10.0.2.10  │
                  │                   │
                  │ IP Forwarding     │
                  │ SNAT / iptables   │
                  └─────────┬─────────┘
                            │
                    Private Subnet
                     10.0.2.0/24
                       │          │
                ┌──────▼─────┐ ┌──▼───────┐
                │  client-1  │ │ client-2 │
                │ 10.0.2.11  │ │10.0.2.x  │
                └────────────┘ └──────────┘
```

### Traffic flow


Private Client
     ↓
Private Route Table
     ↓
Gateway EC2
     ↓
Linux IP Forwarding
     ↓
SNAT
     ↓
Internet Gateway
     ↓
Internet
```

---

## Network Design

| Resource            | Configuration                    |
| ------------------- | -------------------------------- |
| VPC                 | `lab-vpc` — `10.0.0.0/16`        |
| Public subnet       | `public-subnet` — `10.0.1.0/24`  |
| Private subnet      | `private-subnet` — `10.0.2.0/24` |
| Internet Gateway    | `lab-igw`                        |
| Public route table  | `public-rt`                      |
| Private route table | `private-rt`                     |
| Gateway             | Ubuntu 24.04 EC2                 |
| Client 1            | Ubuntu 24.04 EC2                 |
| Client 2            | Ubuntu 24.04 EC2                 |
| SSH                 | Key-based authentication         |
| NAT                 | EC2 + Linux `iptables` SNAT      |

---

# Deployment

## 1. Create the VPC

Create:

```text
Name: lab-vpc
CIDR: 10.0.0.0/16
```

---

## 2. Create the Subnets

### Public subnet

```
Name: public-subnet
CIDR: 10.0.1.0/24
```

### Private subnet

```
Name: private-subnet
CIDR: 10.0.2.0/24
```

---

## 3. Create and Attach the Internet Gateway

Create:

```
Name: lab-igw
```

Attach it to `lab-vpc`.

---

## 4. Configure the Public Route Table

Create:

```
Name: public-rt
```

Associate it with `public-subnet`.

Add:

```
Destination: 0.0.0.0/0
Target: Internet Gateway (lab-igw)
```

---

## 5. Configure the Private Route Table

Create:

```
Name: private-rt
```

Associate it with `private-subnet`.

Add:

```
Destination: 0.0.0.0/0
Target: Gateway EC2 private ENI
```

The private subnet therefore sends Internet-bound traffic to the gateway instance.

---

## 6. Deploy the Gateway EC2 Instance

Launch an Ubuntu 24.04 EC2 instance named:

```
gateway
```

Place its primary network interface in:

```
public-subnet
```

Assign a public IPv4 address.

Create and attach a second ENI:

```
Subnet: private-subnet
Private IP: 10.0.2.10
```

The gateway should therefore have:

```
Public-side interface → 10.0.1.x
Private-side interface → 10.0.2.10
```

Disable **Source/Destination Check** on the gateway ENIs.

---

## 7. Deploy Client EC2 Instances

Launch two Ubuntu 24.04 instances:

```
client-1
client-2
```

Place both in:

```
private-subnet
```

Do **not** assign public IPv4 addresses.

```
client-1 → 10.0.2.11
client-2 → 10.0.2.21
```

Use the same SSH key pair for administrative access.

---

## 8. Configure SSH Access

Use SSH key authentication only.

From the administration machine:

```bash
ssh -A ubuntu@<GATEWAY_PUBLIC_IP>
```

From the gateway:

```bash
ssh ubuntu@<CLIENT_PRIVATE_IP>
```

SSH agent forwarding allows administration of private instances without copying the private SSH key onto the gateway.

---

# 9. Enable IP Forwarding on the Gateway

On the gateway:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

Make it persistent:

```bash
sudo tee /etc/sysctl.d/99-nat-router.conf <<EOF
net.ipv4.ip_forward=1
EOF
```

Apply:

```bash
sudo sysctl --system
```

Verify:

```bash
sysctl net.ipv4.ip_forward
```

Expected:

```
net.ipv4.ip_forward = 1
```

---

# 10. Configure SNAT

On the gateway, configure SNAT for the private subnet.

Replace `<PUBLIC_SIDE_PRIVATE_IP>` with the private IP associated with the gateway's AWS public IPv4 address.

```bash
sudo iptables -t nat -A POSTROUTING \
  -s 10.0.2.0/24 \
  -o ens5 \
  -j SNAT \
  --to-source 10.0.1.131
```

Verify:

```bash
sudo iptables -t nat -L POSTROUTING -n -v
```

---

# 11. Configure Forwarding Rules

Ensure the gateway allows traffic between the private and public interfaces:

```bash
sudo iptables -A FORWARD \
  -i ens6 -o ens5 \
  -s 10.0.2.0/24 \
  -j ACCEPT
```

Allow return traffic:

```bash
sudo iptables -A FORWARD \
  -i ens5 -o ens6 \
  -d 10.0.2.0/24 \
  -m conntrack \
  --ctstate ESTABLISHED,RELATED \
  -j ACCEPT
```

---

# 12. Configure Security Groups

The gateway security group should allow the required management and private-subnet traffic.

Typical rules:

```
SSH (TCP 22)      → administration source
ICMP              → private subnet
Private traffic   → 10.0.2.0/24
```

The private clients should not require inbound Internet access.

For a production implementation, use separate security groups for the gateway and private clients.

---

# 13. Validate Connectivity

From `client-1`:

### Test gateway connectivity

```bash
ping -c 3 10.0.2.10
```

### Test Internet connectivity

```bash
ping -c 3 8.8.8.8
```

### Test DNS and HTTPS

```bash
curl -I https://google.com
```

### Verify the public source IP

```bash
curl -4 https://ifconfig.me
```

The returned IP should be the gateway's public IPv4 address.

Repeat the validation from `client-2`.

---

# 14. Persist NAT Configuration

Install the persistence package:

```bash
sudo apt update
sudo apt install -y iptables-persistent
```

Save the current rules:

```bash
sudo netfilter-persistent save
```

Verify:

```bash
sudo iptables -t nat -L POSTROUTING -n -v
```

The SNAT rule should remain present.

---

# Project Outcome

The completed environment provides:

* Private EC2 instances without public IP addresses
* Centralized Internet egress through a gateway EC2 instance
* Linux-based IP forwarding
* SNAT using `iptables`
* AWS VPC route-table based traffic forwarding
* SSH key-based administration
* Persistent network configuration
* End-to-end connectivity validation

This project demonstrates practical experience with **AWS networking, Linux networking, infrastructure configuration, secure access, troubleshooting, and SRE/DevOps operational practices**.
