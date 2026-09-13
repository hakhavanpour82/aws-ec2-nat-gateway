# Enable IPv4 forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Persist IPv4 forwarding
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-nat-router.conf

sudo sysctl --system

# Configure SNAT
sudo iptables -t nat -A POSTROUTING \
  -s 10.0.2.0/24 \
  -o ens5 \
  -j SNAT \
  --to-source 10.0.1.131

# Allow forwarding
sudo iptables -A FORWARD \
  -i ens6 -o ens5 \
  -s 10.0.2.0/24 \
  -j ACCEPT

sudo iptables -A FORWARD \
  -i ens5 -o ens6 \
  -d 10.0.2.0/24 \
  -m conntrack \
  --ctstate ESTABLISHED,RELATED \
  -j ACCEPT
