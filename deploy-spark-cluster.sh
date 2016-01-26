#!/bin/bash
# Deploys the Spark standalone resource manager on Apcera HCOS
#
# Author: Eugen Feller <eugen.feller@gmail.com>
##############################################################
set -e

APC_COMMAND="/usr/local/bin/apc"
CREATE_CAPSULE="$APC_COMMAND capsule create"
DELETE_CAPSULE="$APC_COMMAND capsule delete"
CONNECT_CAPSULE="$APC_COMMAND capsule connect"
UPDATE_CAPSULE="$APC_COMMAND job update"
ROUTE_ADD="$APC_COMMAND route add auto"
CREATE_NETWORK="$APC_COMMAND network create"
JOIN_NETWORK="$APC_COMMAND network join"
FILECOPY="$APC_COMMAND capsule filecopy"

SPARK_MASTER_NAME="spark-master"
SPARK_MASTER_IP=""
SPARK_WORKER_NAME="spark-worker"
SPARK_IMAGE_NAME="ubuntu-14.04"
SPARK_NETWORK_NAME="spark"
SPARK_UI_PORT="8080"
SPARK_NUMBER_OF_WORKERS=2

function create_network() {
 $CREATE_NETWORK $SPARK_NETWORK_NAME
}

function start_capsule() {
echo "Stating capsule $1"
$CREATE_CAPSULE $1 -i $SPARK_IMAGE_NAME -m 300MB -n 100Mbps -nm 100Mbps -d 3000MB -ae --batch
$JOIN_NETWORK $SPARK_NETWORK_NAME --job $1
}

function start_master_capsule() {
 start_capsule $SPARK_MASTER_NAME
 configure_master_capsule $SPARK_MASTER_NAME
 add_web_route $SPARK_MASTER_NAME
 install_tools $SPARK_MASTER_NAME
 install_spark $SPARK_MASTER_NAME
 start_spark_master $SPARK_MASTER_NAME
}

function start_worker_capsules() {
get_master_ip
for i in `seq 1 $SPARK_NUMBER_OF_WORKERS`;
do
 local worker_name=${SPARK_WORKER_NAME}-$i
 echo "Provisioning worker $worker_name"
 start_capsule $worker_name
 configure_slave_capsule $worker_name $SPARK_MASTER_IP
 install_tools $worker_name
 install_spark $worker_name
 start_spark_worker $worker_name $SPARK_MASTER_IP
done
}

function configure_master_capsule() {
$CONNECT_CAPSULE $1 <<EOF
ifconfig | grep 192 | grep 'inet addr:' | cut -d: -f2 | awk '{ print \$1}' > /tmp/current_ip
echo \$(ifconfig | grep 192 | grep 'inet addr:' | cut -d: -f2 | awk '{ print \$1}') $1 >> /etc/hosts
echo "$1" > /etc/hostname
hostname $1
EOF
}

function configure_slave_capsule() {
$CONNECT_CAPSULE $1 <<EOF
echo "$2 $SPARK_MASTER_NAME" >> /etc/hosts
echo \$(ifconfig | grep 192 | grep 'inet addr:' | cut -d: -f2 | awk '{ print \$1}') $1 >> /etc/hosts
echo "$1" > /etc/hostname
hostname $1
EOF
}

function add_web_route() {
$UPDATE_CAPSULE $1 --port-add $SPARK_UI_PORT --batch -o
$ROUTE_ADD --app $1 -p $SPARK_UI_PORT --batch --tcp
}

function install_tools() {
$CONNECT_CAPSULE $1 <<EOF
apt-get -y update
apt-get install -y --no-install-recommends vim netcat-traditional openjdk-7-jdk
update-alternatives --set nc /bin/nc.traditional
EOF
}

function copy_file_to_local() {
$FILECOPY $1 -r "$2" -dl $3
}

function install_spark() {
$CONNECT_CAPSULE $1 <<EOF
wget http://d3kbcqa49mib13.cloudfront.net/spark-1.4.1-bin-hadoop2.6.tgz -O /root/spark-1.4.1-bin-hadoop2.6.tgz
tar -xzvf /root/spark-1.4.1-bin-hadoop2.6.tgz
ln -s /root/spark-1.4.1-bin-hadoop2.6 /root/spark
EOF
}

function start_spark_master() {
$CONNECT_CAPSULE $1 <<EOF
export SPARK_MASTER_IP=\$(ifconfig | grep 192 | grep 'inet addr:' | cut -d: -f2 | awk '{ print \$1}')
/root/spark/sbin/start-master.sh
EOF
}

function start_spark_worker() {
$CONNECT_CAPSULE $1 <<EOF
/root/spark/sbin/start-slave.sh spark://$2:7077
EOF
}

function get_master_ip() {
 copy_file_to_local $SPARK_MASTER_NAME "/tmp/current_ip" "current_ip"
 SPARK_MASTER_IP=`cat current_ip`
}

for i in "$@"
do
case $i in
    -n)
    create_network
    ;;
    -m)
    start_master_capsule
    ;;
    -w)
    start_worker_capsules
    ;;
    *)
    echo "Unknown option selected!"
    ;;
esac
done
