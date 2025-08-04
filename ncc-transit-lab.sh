#!/bin/bash

# Set environment variables
REGION1="europe-west1"
REGION2="us-west1"
ZONE1="europe-west1-b"
ZONE2="us-west1-b"


# Enable required API
gcloud services enable networkconnectivity.googleapis.com

# Delete default network
gcloud compute networks delete default --quiet

# Create VPC networks
gcloud compute networks create vpc-transit --bgp-routing-mode=global --subnet-mode=custom

gcloud compute networks create vpc-a --bgp-routing-mode=regional --subnet-mode=custom
gcloud compute networks subnets create vpc-a-sub1-use4 \
  --network=vpc-a --region=$REGION1 --range=10.20.10.0/24

gcloud compute networks create vpc-b --bgp-routing-mode=regional --subnet-mode=custom
gcloud compute networks subnets create vpc-b-sub1-usw2 \
  --network=vpc-b --region=$REGION2 --range=10.20.20.0/24

# Create Cloud Routers
gcloud compute routers create cr-vpc-transit-use4-1 --network=vpc-transit --region=$REGION1 --asn=65000
gcloud compute routers create cr-vpc-transit-usw2-1 --network=vpc-transit --region=$REGION2 --asn=65000
gcloud compute routers create cr-vpc-a-use4-1 --network=vpc-a --region=$REGION1 --asn=65001
gcloud compute routers create cr-vpc-b-usw2-1 --network=vpc-b --region=$REGION2 --asn=65002

# Create VPN gateways
gcloud compute vpn-gateways create vpc-transit-gw1-use4 --network=vpc-transit --region=$REGION1
gcloud compute vpn-gateways create vpc-transit-gw1-usw2 --network=vpc-transit --region=$REGION2
gcloud compute vpn-gateways create vpc-a-gw1-use4 --network=vpc-a --region=$REGION1
gcloud compute vpn-gateways create vpc-b-gw1-usw2 --network=vpc-b --region=$REGION2

# Helper function to create tunnels and BGP
create_vpn_pair() {
  LOCAL_GATEWAY=$1
  REMOTE_GATEWAY=$2
  LOCAL_ROUTER=$3
  REGION=$4
  PREFIX=$5
  LOCAL_ASN=$6
  REMOTE_ASN=$7
  IP1=$8
  IP2=$9
  IP3=${10}
  IP4=${11}

  gcloud compute vpn-tunnels create $PREFIX-tu1 \
    --region=$REGION \
    --peer-gcp-gateway=$REMOTE_GATEWAY \
    --vpn-gateway=$LOCAL_GATEWAY \
    --interface=0 \
    --shared-secret=gcprocks \
    --ike-version=2 \
    --router=$LOCAL_ROUTER \
    --bgp-peer-name=${PREFIX}-bgp1 \
    --peer-asn=$REMOTE_ASN \
    --router-ip-address=$IP1 \
    --peer-ip-address=$IP2

  gcloud compute vpn-tunnels create $PREFIX-tu2 \
    --region=$REGION \
    --peer-gcp-gateway=$REMOTE_GATEWAY \
    --vpn-gateway=$LOCAL_GATEWAY \
    --interface=1 \
    --shared-secret=gcprocks \
    --ike-version=2 \
    --router=$LOCAL_ROUTER \
    --bgp-peer-name=${PREFIX}-bgp2 \
    --peer-asn=$REMOTE_ASN \
    --router-ip-address=$IP3 \
    --peer-ip-address=$IP4
}

# Create VPN tunnels and BGP sessions for vpc-transit <-> vpc-a
create_vpn_pair vpc-transit-gw1-use4 vpc-a-gw1-use4 cr-vpc-transit-use4-1 $REGION1 transit-to-vpc-a 65000 65001 169.254.1.1 169.254.1.2 169.254.1.5 169.254.1.6
create_vpn_pair vpc-a-gw1-use4 vpc-transit-gw1-use4 cr-vpc-a-use4-1 $REGION1 vpc-a-to-transit 65001 65000 169.254.1.2 169.254.1.1 169.254.1.6 169.254.1.5

# Create VPN tunnels and BGP sessions for vpc-transit <-> vpc-b
create_vpn_pair vpc-transit-gw1-usw2 vpc-b-gw1-usw2 cr-vpc-transit-usw2-1 $REGION2 transit-to-vpc-b 65000 65002 169.254.1.9 169.254.1.10 169.254.1.13 169.254.1.14
create_vpn_pair vpc-b-gw1-usw2 vpc-transit-gw1-usw2 cr-vpc-b-usw2-1 $REGION2 vpc-b-to-transit 65002 65000 169.254.1.10 169.254.1.9 169.254.1.14 169.254.1.13

# Create NCC Hub
gcloud alpha network-connectivity hubs create transit-hub --description="Transit_hub"

# Create NCC Spokes
gcloud alpha network-connectivity spokes create bo1-tunnel1 \
  --hub=transit-hub --description="BO1-Tunnel1" \
  --vpn-tunnel=transit-to-vpc-a-tu1 \
  --region=$REGION1

gcloud alpha network-connectivity spokes create bo1-tunnel2 \
  --hub=transit-hub --description="BO1-Tunnel2" \
  --vpn-tunnel=transit-to-vpc-a-tu2 \
  --region=$REGION1

gcloud alpha network-connectivity spokes create bo2-tunnel1 \
  --hub=transit-hub --description="BO2-Tunnel1" \
  --vpn-tunnel=transit-to-vpc-b-tu1 \
  --region=$REGION2

gcloud alpha network-connectivity spokes create bo2-tunnel2 \
  --hub=transit-hub --description="BO2-Tunnel2" \
  --vpn-tunnel=transit-to-vpc-b-tu2 \
  --region=$REGION2

# Create firewall rules
gcloud compute firewall-rules create fw-a \
  --network=vpc-a --allow tcp:22,icmp --direction=INGRESS --source-ranges=0.0.0.0/0

gcloud compute firewall-rules create fw-b \
  --network=vpc-b --allow tcp:22,icmp --direction=INGRESS --source-ranges=0.0.0.0/0

# Create VM in vpc-a
gcloud compute instances create vpc-a-vm-1 \
  --zone=$ZONE1 \
  --machine-type=e2-medium \
  --subnet=vpc-a-sub1-use4 \
  --image-family=debian-11 --image-project=debian-cloud \
  --boot-disk-size=10GB

# Create VM in vpc-b
gcloud compute instances create vpc-b-vm-1 \
  --zone=$ZONE2 \
  --machine-type=e2-medium \
  --subnet=vpc-b-sub1-usw2 \
  --image-family=debian-11 --image-project=debian-cloud \
  --boot-disk-size=10GB

echo "\n✅ Setup complete. You can now SSH into vpc-a-vm-1 and ping the internal IP of vpc-b-vm-1 to test connectivity."

