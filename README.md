## 环境准备

   我们需要一个etcd作为calico ip 以及profile等的数据库, 需要准备安装calico
   相关的工具包。

> 1. 两个Centos7.1 环境 node1|2(物理机，VM 均可)，假定 IP 为：192.168.20.1,
>    192.168.20.2
> 2. 为了简单，请将 node1|2 上的 Iptables INPUT 策略设为 ACCEPT，同时安装Docker 
>    我们测试版本为`1.12.1-1.el7`
> 3. 一个可访问的 Etcd 集群（192.168.20.1:2379），Calico使用其进行数据存放和节点发现 


## etcd数据库的安装

   我们安装单节点etcd数据库，我们只需要在node1机器上安装就可以了

   ```
   node1# yum install etcd
   ```
   
   然后修改文件`/etc/etcd/etcd.conf` 文件

   > ETCD_LISTEN_CLIENT_URLS="http://192.168.20.1:2379"
   > ETCD_ADVERTISE_CLIENT_URLS="http://192.168.20.1:2379"

  然后配置etcd自动启动，并且启动etcd服务

  ```
  node1# systemctl enable etcd.service
  node1# systemctl start etcd.service
  ```


## Docker服务安装

   Docker服务必须都安装在node1和node2节点上。安装步骤如下

### 配置docker 安装源

   vim  /etc/yum.repos.d/docker.repo
>  [dockerrepo]
>  name=Docker Repository
>  baseurl=https://yum.dockerproject.org/repo/main/centos/$releasever/
>  enabled=1
>  gpgcheck=1
>  gpgkey=https://yum.dockerproject.org/gpg
 
### 安装docker
   ```
   node1|node2# yum install docker-engine
   ```  
### 修改正docker无法启动bug
   docker1.12.1-1.el7在centos7.2 可能会无法启动， 通过配置文件修正
   vim /usr/lib/systemd/system/docker.socket

> [Unit]
> Description=Docker Socket for the API
> PartOf=docker.service

> [Socket]
> ListenStream=/var/run/docker.sock
> SocketMode=0660
> SocketUser=root
> SocketGroup=docker

> [Install]
> WantedBy=sockets.target

  通知系统重新加载服务
  ```
  node1|node2 #systemctl daemon-reload
  ```

  关闭防护墙
  ```
  systemctl disable firewalld
  systemctl stop firewalld
  ```


  启动docker
  ```
  node1|node2# systemctl enable docker.service
  node1|node2# systemctl start docker.service

  ```
 
## 安装calico环境

   calico 环境必须安装在所以的docker机器上面，calico环境包含calicoctl， 以及calico/node 和 
   libnetweork两个容器。

### 下载calicoctl.
  
   当前试验版本`0.21.0-dev`, calicoctl用于下载calico环境所需要容器，创建网络ip池，以及子网的profile。
   下载calicoctl到/usr/bin目录
   ```
   node1|node2# curl -L http://www.projectcalico.org/builds/calicoctl -o /usr/bin/calicoctl
   node1|node2# chmod +x /usr/local/bin/calicoctl
   ```

### 配置calicoctl环境变量

   node1|node2# vim .bashrc
  
> export ETCD_AUTHORITY=192.168.20.1:2379

  其中192.168.20.1:2379 etcd ip地址和端口和号

   ```
   node1|node2# source .bashrc
   ```

### 启动calico服务
   通过机器本地ip启动calico/node以及libnetwork, 所有docker节点都必须执行下面命令

   ````
   node1# calicoctl node --ip=192.168.20.1 --libnetwork
   node2# calicoctl node --ip=192.168.20.2 --libnetwork
   ```

   工具自动pull最新版本的calico/node以及libnetwork 并且启动

   ## 修改docker 启动参数支持calico
      vim /etc/systemd/system/docker.service.d/override.conf

> [Service]
> ExecStart=
> ExecStart=/usr/bin/dockerd -H unix:///var/run/docker.sock --cluster-store=etcd://192.168.20.1:2379


  其中是etcd部署的ip地址192.168.20.1:2379 

  然后重新relaod systemd
  node1|node2 #systemctl daemon-reload
  然后需要重新启动docker服务才可以生效

  ```
  node1|node2# systemctl restart docker.service、
  ```
## 配置自动启动calico容器服务

## 使用calico网络插件对网络进行配置

### 添加网段

#### a) Networking using Calico IPAM in a non-cloud environment
   For Calico IPAM in a non-cloud environment, you need to first create a Calico IP Pool with no additional options. Here we create a pool with CIDR 192.168.21.0/24.
    ```
    calicoctl pool add 192.168.21.0/24
    ```

#### b)  Networking using Calico IPAM in a cloud environment
   For Calico IPAM in a cloud environment that doesn't enable direct container to container communication (DigitalOcean, GCE), you need to first create a Calico IP Pool using the calicoctl pool add command specifying the ipip and nat-outgoing options. Here we create a pool with CIDR 192.168.22.0/24


### 添加calico网络，以及制定子网 

    我们使用calico IPAM 驱动添加网络， 并且制定网络的子网。 例如我们添加一个子网，`192.168.22.0/24` 给web前端网络使用，步骤为

- 创建calico ip pool
- 创建docker网络使用这个ip pool
- 创建docker容器并且制定ip地址

```
calicoctl pool add 192.168.22.0/24
docker network create --driver calico --ipam-driver calico --subnet=192.168.22.0/24 web
docker run --net web --name grafana_web --ip 192.168.22.100 -tid grafana/grafana
```

如果有IPAM 自动分配ip地址
docker run --net web --name grafana_web -tid grafana/grafana
