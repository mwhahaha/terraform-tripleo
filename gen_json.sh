#!/bin/bash
set -e
NODE_ARCH="x86_64"
NODE_PREFIX="domain-baremetal"
PM_HOST="10.109.0.1"
PM_USER="admin"
PM_PASS="password"
PM_PORT_BASE=16000

NODES=$(sudo virsh list --all | grep "$NODE_PREFIX" | awk '{print $2 }')
JSON=$(jq "." <<EOF
{
    "nodes":[],
    "arch":"${NODE_ARCH}",
    "host-ip":"$PM_HOST",
    "seed-ip":""
}
EOF
)

COUNT=0
for NODE in $NODES; do
    XML="$(sudo virsh dumpxml $NODE)"
    PORTS=$(echo "$XML" | grep 'mac address' | cut -d "'" -f 2)
    PM_PORT=$(($PM_PORT_BASE + $COUNT))
    JSON=$(jq \
            --arg macs "${PORTS}" \
            ".nodes=(.nodes + [{ pm_addr:\"${PM_HOST}\", pm_password:\"${PM_PASS}\", pm_type:\"ipmi\", pm_user:\"${PM_USER}\", pm_port:\"${PM_PORT}\", arch:\"${NODE_ARCH}\", mac:\$macs | split (\"\n\")}])" \
            <<< $JSON)
    COUNT=$(($COUNT + 1))
done
jq . <<< $JSON
