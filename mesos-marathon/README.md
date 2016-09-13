## 0 基本环境

     例子是使用6台机器搭建mesos+marathon集群，操作系统是centos7 
| IP 地址       | 角色                                      | 
| ------------- |:-----------------------------------------:|
| 192.168.20.1  | zookeeper,mesos-master,mesos-slave, docker|
| 192.168.20.2  | zookeeper,mesos-master,mesos-slave, docker|
| 192.168.20.3  | zookeeper,mesos-master,mesos-slave, docker|
| 192.168.20.4  | mesos-slave, docker, marathon             |
| 192.168.20.5  | mesos-slave, docker                       |
| 192.168.20.6  | mesos-slave, docker                       |
     

## 1 安装mesos-master node

### 1.1 安装zookeeper

   mesos master的节点是通过zookeeper进行消息通信，mesos-master安装节点同时安装zookeeper。安装步骤:

- 在所有master节点添加安装源
```
   mesos-master# yum install http://repos.mesosphere.com/el/7/noarch/RPMS/mesosphere-el-repo-7-1.noarch.rpm
```

- 安装 zonekeeper
```
   mesos-master# yum -y install mesosphere-zookeeper
```

### 1.2 配置zookeeper

- Zookeeper server ID 号配置
    给每台mesos-master node zookeeper 配置id。 Id 号配置在文件`/var/lib/zookeeper/myid`, 每台机器id必须唯一，而且是1～255之间。

- 服务器地址配置
  给每台mesos-master node zookeeper 配置服服务器地址，地址追加到文件`/etc/zookeeper/conf/zoo.cfg`

```
server.1=192.168.20.1:2888:3888
server.2=192.168.20.2:2888:3888
server.3=192.168.20.3:2888:3888
```
格式是`server.id=ip:2888:3888`

- 所以mesos-master node zookeeper配置完毕以后可以启动

```
mesos-master# systemctl start zookeeper
mesos-master# systemctl enable zookeeper
```

### 1.3 mesos master install 
   
   mesos-master 相当与集群中心管理节点，用于集群资源管理，任务分配。mesos-slave如果用于docker环境，
相当于生产docker容器host机器。
   由于centos7没有官方mesos安装源，所以添加`mesosphere`提供安装源
```
mesos-master# yum install http://repos.mesosphere.com/el/7/noarch/RPMS/mesosphere-el-repo-7-1.noarch.rpm
mesos-master# yum -y install mesos
```

### 1.4 配置mesos的zookeeper

   每个mesos-master, 需要配置`/etc/mesos/zk`文件,指向对应zookeepe服务器，端口，格式`zk://zookeeper_ip:2181/mesos`. 如果有多
台机器组成的zookeeper集群, 每个ip地址需要以`，`分割, 格式是`zk://zookeeper_ip_1:2181,zookeeper_ip_2:2181,zookeeper_ip_3:2181/mesos`。
上面环境配置如下:
```
zk://192.168.20.1:2181,192.168.20.2:2181,192.168.20.3:2181/mesos
```

### 1.5 配置mesos-master集群数目

  集群`quorum`大小配置公式如下
```
  quorum = int(mesos-master总数/2) + 1
```

  如果一个mesos集群有3台机器，`3/2+1=2`， 所以每台master机器需要配置`/etc/mesos-master/quorum`文件，制定`quorum`为2.
当mester存活数目小于2, 集群不可用。

### 1.6 配置mesos-master机器hostname和ip
    建议把mesos配置文件hostname和ip配置为ip模式，方便通讯。配置master节点的识别ip和hostname（以master1节点为例）

```
mesos-master# echo 192.168.20.1 | sudo tee /etc/mesos-master/ip
mesos-master# sudo cp /etc/master-slave/ip /etc/mesos-master/hostname
```

## 2 安装mesos-slave node

### 2.1 安装mesos-slave
   mesos master的节点是通过zookeeper进行消息通信，mesos-master安装节点同时安装zookeeper。安装步骤:

- 在所有master节点添加安装源
```
 mesos-slave# yum install http://repos.mesosphere.com/el/7/noarch/RPMS/mesosphere-el-repo-7-1.noarch.rpm
```

- 安装 zonekeeper
```
 mesos-slave# eyum -y install mesos mesosphere-zookeeper
```

### 2.2 配置mesos的zookeeper

   每个mesos-slave, 需要配置`/etc/mesos/zk`文件,指向对应zookeepe服务器，端口，格式`zk://zookeeper_ip:2181/mesos`. 如果有多set /etc/mesos/zk to:
台机器组成的zookeeper集群, 每个ip地址需要以`，`分割, 格式是`zk://zookeeper_ip_1:2181,zookeeper_ip_2:2181,zookeeper_ip_3:2181/mesos`。
上面环境配置如下:
```
zk://192.168.20.1:2181,192.168.20.2:2181,192.168.20.3:2181/mesos
```

### 2.3 配置mesos-slave机器hostname和ip
    建议把mesos配置文件hostname和ip配置为ip模式，方便通讯。配置master节点的识别ip和hostname（以master1节点为例）
```
mesos-slave# echo 192.168.20.1 | sudo tee /etc/mesos-master/ip
mesos-slave# sudo cp /etc/master-slave/ip /etc/mesos-master/hostname
```

### 2.4 配置mesos containers类型
    配置mesos-slave 调用docker，如果没有就无法使用。需要配置每个mesos-slave节点
```
mesos-slave# echo "docker,mesos" > /etc/mesos-slave/containerizers
```

### 2.5 启动mesos-slave，并且设置自动启动
```
mesos-slave# systemctl enable mesos-slave
mesos-slave# systemctl start mesos-slave
```

  配置好mesos集群以后可以通过浏览其查看是否部署成功: http://mesos_master_ip:5050

## 3 Matathon 安装和配置

### 3.1 marathon 最新版下载
wget http://downloads.mesosphere.com/marathon/v1.1.1/marathon-1.1.1.tgz

### 3.2 启动 marathon 
  解压后进入目录`marathon-1.1.1/bin`
 
  mesos-master集群消息任务zookeeper zk://192.168.20.1:2181,192.168.20.2:2181,192.168.20.3:2181/mesos
  matathon集群zookeeper zk://192.168.20.1:2181,192.168.20.2:2181,192.168.20.3:2181/marathon

  所以matathon启动命令是:
```
   ./start --master zk://192.168.20.1:2181,192.168.20.2:2181,192.168.20.3:2181/mesos --zk zk://192.168.20.1:2181,192.168.20.2:2181,192.168.20.3:2181/marathon
```

### 3.3 创建calico网络container

   通过浏览器进入页面，点击`Create Application`, 以后可以通过json启动contianer

```
{
    "id": "web",
    "instances": 3,
    "mem": 64,
    "cpus": 0.1,
    "ipAddress": {
        "discovery": {
            "ports": [{"number": 80, "name": "http", "protocol": "tcp"}]
        }
    },
    "container": {
        "type": "DOCKER",
        "docker": {
            "image": "calico/hello-dcos:v0.1.0",
            "parameters": [{"key": "net", "value": "web"}]
        }
    },
    "labels": {
      "HAPROXY_GROUP": "external",
      "HAPROXY_0_VHOST": "spring.acme.org"
    }
}
```

上面例子是自动获取ip地址， 如果需要配置ip地址

```
{
    "id": "web",
    "instances": 3,
    "mem": 64,
    "cpus": 0.1,
    "ipAddress": {
        "discovery": {
            "ports": [{"number": 80, "name": "http", "protocol": "tcp"}]
        }
    },
    "container": {
        "type": "DOCKER",
        "docker": {
            "image": "calico/hello-dcos:v0.1.0",
            "parameters": [{"key": "net", "value": "web"}, {"key": "ip", "value": "192.168.21.1"}]
        }
    },
    "labels": {
      "HAPROXY_GROUP": "external",
      "HAPROXY_0_VHOST": "spring.acme.org"
    }
}
```

