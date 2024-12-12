#!/usr/bin/env bash

NEW_IP="$1"
if [ -z "$NEW_IP" ]; then
    echo "Kullanım: $0 <YENI_IP>"
    exit 1
fi

ORIGINAL_CONF="/etc/openvpn/server.conf"
INCREMENT_FILE="/etc/openvpn/increments.txt"
BASE_PORT=1194
BASE_SECOND_OCTET=8 # Başlangıç subnet: 10.8.x.0

if [ ! -f "$ORIGINAL_CONF" ]; then
    echo "Orijinal server.conf bulunamadı: $ORIGINAL_CONF"
    exit 1
fi

if [ ! -f "$INCREMENT_FILE" ]; then
    echo "increments.txt bulunamadı, oluşturuluyor..."
    mkdir -p /etc/openvpn
    echo "INDEX=1" > $INCREMENT_FILE
fi

source $INCREMENT_FILE

# İlk eklemede INDEX=1 olduğundan port = 1194+1 = 1195 olacak
NEW_PORT=$((BASE_PORT + INDEX))

# Subnet hesaplama
OFFSET=$INDEX
SECOND_OCTET=$((BASE_SECOND_OCTET + (OFFSET / 256)))
THIRD_OCTET=$((OFFSET % 256))
NEW_SUBNET="10.${SECOND_OCTET}.${THIRD_OCTET}.0"

NEW_CONF="/etc/openvpn/server${NEW_PORT}.conf"

cp $ORIGINAL_CONF $NEW_CONF

# Orijinal conf'ta local satırı yoksa en başa ekle
if ! grep -q "^local " $NEW_CONF; then
    sed -i "1ilocal ${NEW_IP}" $NEW_CONF
else
    sed -i "s/^local .*/local ${NEW_IP}/" $NEW_CONF
fi

# proto udp6 => proto udp
sed -i 's/^proto udp6/proto udp/' $NEW_CONF

# port güncelle
sed -i "s/^port .*/port ${NEW_PORT}/" $NEW_CONF

# server satırını güncelle
# Orijinalde "server 10.8.0.0 255.255.255.0" olduğunu varsayıyoruz.
# Onu NEW_SUBNET ile değiştiriyoruz.
sed -i "s|^server 10\.8\.0\.0 255\.255\.255\.0|server ${NEW_SUBNET} 255.255.255.0|" $NEW_CONF

# iptables NAT kuralı
iptables -t nat -A POSTROUTING -s ${NEW_SUBNET}/24 -o ens18 -j SNAT --to-source ${NEW_IP}

# Systemd service
SERVICE_NAME="openvpn@server${NEW_PORT}"
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

if [ $? -ne 0 ]; then
    echo "${SERVICE_NAME} başlatılamadı. journalctl -xe ile kontrol edin."
    exit 1
fi

echo "${NEW_IP} ip adresiyle yeni OpenVPN instance oluşturuldu:"
echo "Port: ${NEW_PORT}"
echo "Subnet: ${NEW_SUBNET}"
echo "Servis: ${SERVICE_NAME}"
echo "Config: ${NEW_CONF}"

# INDEX artır
NEW_INDEX=$((INDEX + 1))
echo "INDEX=${NEW_INDEX}" > $INCREMENT_FILE
