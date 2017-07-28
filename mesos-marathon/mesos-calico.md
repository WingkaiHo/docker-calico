## 1.Calico-mesos 基础环境安装

###1.1 calicoctl 二进制文件安装\

```
$sudo wget -O /usr/local/bin/calicoctl https://github.com/projectcalico/calicoctl/releases/download/v1.3.0/calicoctl
$sudo chmod +x /usr/local/bin/calicoctl
```

###1.2 加载calico node

命令模式
```
$sudo ETCD_ENDPOINTS=http://$ETCD_IP:$ETCD_PORT calicoctl node run --node-image=quay.io/calico/node:v1.3.0
```

systemd 模式
```
vim /etc/sysconfig/calico
ETCD_ENDPOINTS=http://<etcd-ip>:2379 
ETCD_CA_FILE=""                 
ETCD_CERT_FILE=""               
ETCD_KEY_FILE=""                
```

###1.3 下载cni插件
```
mesos-slave$ mkdir -p /opt/cni/bin/
mesos-slvae$ cd /opt/cni/bin/
mesos-slave$ wget https://github.com/projectcalico/cni-plugin/releases/download/v1.9.1/calico 
mesos-slave$ wget https://github.com/projectcalico/cni-plugin/releases/download/v1.9.1/calico-ipam
mesos-slave$ chmod +x *
```

###1.13.1 编辑ip pool 文件
```
$vim ip-pool.yml

apiVersion: v1
kind: ipPool
metadata:
  cidr: 173.19.0.0/16
spec:
  ipip:
    enabled: true
    mode: cross-subnet
  nat-outgoing: true
  disabled: false

```



###1.4 配置mesos-slave cni 插件模式

###1.4.1 创建calico mesos-slave cni config

```
mesos-slave$ mkdir -p /etc/cni/net.d/
mesos-slave$ cat > /etc/cni/net.d/calico.conf <<EOF
{
   "name": "calico",
   "cniVersion": "0.1.0",
   "type": "calico",
   "ipam": {
       "type": "calico-ipam"
   },
   "etcd_endpoints": "http://etcd_ip:2379"
}
EOF
```

###1.4.2 mesos-slave 启动参数

服务方式启动:
```
sudo mesos-slave --master=<master IP> --ip=<Agent IP>
  --work_dir=/var/lib/mesos
  --network_cni_config_dir=/etc/cni/net.d/
  --network_cni_plugins_dir=/opt/cni/bin
```

docker-compose 方式
```
version: '2'

services:

  dcos-slave:
    image: mesos-slave:1.1.0
    network_mode: "host"
    container_name: "meoso-slave"
    restart : "always"
    pid: "host"
    privileged: true
    volumes:
      - /opt/mesos/slave:/var/lib/mesos
      - /etc/localtime:/etc/localtime:ro
      - /sys/fs/cgroup:/sys/fs/cgroup
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/mesos/cni/:/opt/mesos/cni/

    environment:
      MESOS_PORT: "5051"
      MESOS_HOSTNAME: "<host-ip>"
      MESOS_IP: "<host-ip>"
      MESOS_MASTER: "zk://master-1:2181,master-2:2181,master-3:2181/mesos"
      MESOS_LOG_DIR: "/var/lib/mesos/log"
      MESOS_WORK_DIR: "/var/lib/mesos"
      MESOS_isolation: "cgroups/cpu,cgroups/mem"
      MESOS_executor_registration_timeout: "5mins"
      MESOS_ATTRIBUTES: "file:///var/lib/mesos/config/attributes"
      MESOS_CONTAINERIZERS: "docker,mesos"
      MESOS_NETWORK_CNI_CONFIG_DIR: "/etc/cni/net.d/"
      MESOS_NETWORK_CNI_PLUGINS_DIR: "/opt/cni/bin"
```

###1.5 docker 配置Cluster Store

   docker 启动参数需要添加

```
--cluster-store=etcd://$ETCD_IP:$ETCD_PORT
```
   重新启动docker


###2 docker 环境配置

--cluster-store=etcd://$ETCD_IP:$ETCD_PORT

###2.1 创建calico网络

```
$ docker network create --driver calico --ipam-driver calico-ipam net1

```

指定对应的网段
```
$ docker network create --driver calico --ipam-driver calico-ipam --subnet=192.0.2.0/24 my_net
```

网段必须在地址池存在

###2.2 配置mesos-dns

###2.2.1 配置dns配置文件
```
{
  "zk": "zk://zookeeper-ip:2181:/mesos",
  "masters": ["mesos:5050"],
  "refreshSeconds": 5,
  "ttl": 60,
  "domain": "mesos",
  "port": 53,
  "resolvers": ["114.114.114.114"],
  "timeout": 5,
  "httpon": true,
  "dsnon": true,
  "httpport": 8123,
  "externalon": true,
  "listener": "0.0.0.0",
  "SOAMname": "root.ns1.mesos",
  "SOARname": "ns1.mesos",
  "SOARefresh": 60,
  "SOARetry":   600,
  "SOAExpire":  86400,
  "SOAMinttl": 60,
  "IPSources": ["netinfo", "mesos", "host"]
}

```

###2.2.2 启动mesos-dns

```
docker run -d --net=host -v "$(pwd)/config.json:/config.json" -v "$(pwd)/logs:/tmp" mesosphere/mesos-dns:0.5.2 /usr/bin/mesos-dns -v=2 -config=/config.json
```

<task-name>.marathon.mesosi
