## 环境准备

   我们需要一个etcd作为calico ip 以及profile等的数据库, 需要准备安装calico
   相关的工具包。

> 1. 两个Centos7.1 环境 node1|2(物理机，VM 均可)，假定 IP 为：192.168.20.1,
>    192.168.20.2
> 2. 为了简单，请将 node1|2 上的 Iptables INPUT 策略设为 ACCEPT，同时安装Docker 
>    我们测试版本为`1.12.1-1.el7`
> 3. 一个可访问的 Etcd 集群（192.168.20.1:2379），Calico使用其进行数据存放和节点发现 
> 4. 两个节点需要配置calicoctl，版本为`0.21.0-dev`


## Etcd数据库的安装

   我们安装单节点etcd数据库，我们只需要在node1机器上安装就可以了

```
 node1# yum install etcd
```
   
   然后修改文件
```
  node1# vim /etc/etcd/etcd.conf
```
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
> \[dockerrepo\]
>
> name=Docker Repository
>
> baseurl=https://yum.dockerproject.org/repo/main/centos/$releasever/
>
> enabled=1
>
> gpgcheck=1
>
> gpgkey=https://yum.dockerproject.org/gpg
 
### 安装docker
```
 node1|node2# yum install docker-engine
```


### 修改正docker无法启动bug
   docker1.12.1-1.el7在centos7.2 可能会无法启动， 通过配置文件修正
   vim /usr/lib/systemd/system/docker.socket

> \[Unit\]
>
> Description=Docker Socket for the API
> PartOf=docker.service

> \[Socket\]
>
> ListenStream=/var/run/docker.sock
> SocketMode=0660
> SocketUser=root
> SocketGroup=docker

> \[Install\]
>
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

   calico 环境必须安装在所以的docker机器上面，calico环境包含calicoctl， 以及calico-node 和 
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

```
 node1# calicoctl node --ip=192.168.20.1 --libnetwork
 node2# calicoctl node --ip=192.168.20.2 --libnetwork
```

   工具自动pull最新版本的calico/node以及libnetwork 并且启动

## 修改docker 启动参数支持calico
  vim /etc/systemd/system/docker.service.d/override.conf
> \[Service\]
>
> ExecStart=
> 
> ExecStart=/usr/bin/dockerd -H unix:///var/run/docker.sock --cluster-store=etcd://192.168.20.1:2379


  其中是etcd部署的ip地址192.168.20.1:2379 

  然后重新relaod systemd
  node1|node2 #systemctl daemon-reload
  然后需要重新启动docker服务才可以生效

```
node1|node2# systemctl restart docker.service
```
## 配置自动启动calico容器服务
   Calico 服务container有两个， 分别是calico-node和calico-libnetwork, 如果系统机器重新启动以后，这两个插件的容器
是不会随docker启动而启动。如果需要配置自动启动，配置步骤如下:

   创建服务文件`/usr/lib/systemd/system/calico-node.service`,内容为:
> \[Unit\]
>
> Description=calico-node
>
> Requires=docker.service
>
> After=docker.service
>
> \[Service\]
> Restart=always
>
> ExecStart=/usr/bin/docker start -a calico-node
>
> ExecStop=/usr/bin/docker stop -t 2 calico-node
>
> \[Install\]
>
> WantedBy=multi-user.target

  创建服务文件`/usr/lib/systemd/system/calico-libnetwork.service`
> \[Unit\]
>
> Description=calico-libnetwork
>
> Requires=docker.service calico-node.service
>
> After=docker.service calico-node.service
>
> \[Service\]
>
> Restart=always
>
> ExecStart=/usr/bin/docker start -a calico-libnetwork
>
> ExecStop=/usr/bin/docker stop -t 2 calico-libnetwork
>
> \[Install\]
> WantedBy=multi-user.target


## 使用calico网络插件对网络进行配置

### 添加网段

#### a) Networking using Calico IPAM in a non-cloud environment
   For Calico IPAM in a non-cloud environment, you need to first create a Calico IP Pool with no additional options. Here we create a pool with CIDR 192.168.21.0/24.
```
  calicoctl pool add 192.168.21.0/24
```

#### b)  Networking using Calico IPAM in a cloud environment
   For Calico IPAM in a cloud environment that doesn't enable direct container to container communication (DigitalOcean, GCE), you need to first create a Calico IP Pool using the calicoctl pool add command specifying the ipip and nat-outgoing options. Here we create a pool with CIDR 192.168.22.0/24

```
   calicoctl pool add 192.168.21.0/24 --nat-outgoing --ipip 
```
   支持跨子网的主机上的Docker间网络互通，需要添加--ipip参数；如果要Docker访问外网，需要添加--nat-outgoing参数。

#### 查看已经添加网段

   可以通过下面的命令已经创建的子网
```
   calicoctl pool show 
```

### 添加calico网络，以及制定子网，添加容器
    我们使用calico IPAM 驱动添加网络， 并且制定网络的子网。 例如我们添加一个子网，`192.168.22.0/24` 给web前端网络使用，步骤为

- 创建calico ip pool
- 创建docker网络使用这个ip pool
- 创建docker容器并且制定ip地址

```
node1# calicoctl pool add 192.168.22.0/24
node1# docker network create --driver calico --ipam-driver calico --subnet=192.168.22.0/24 web
node1# docker run --net web --name container_1 --ip 192.168.22.1 -tid centos
```

   如果选择IPAM自动分配ip地址， 命令如下
```
node1# docker run --net web --name container -tid centos
```
   注意自动分配，容器停止/重新启动以后，ip地址会产生变化。

### 查看已经创建的网络

    创建calico的网络以后在`node1 | node2`两个节点上都可以查看的到，因为网络信息记录在`etcd`的数据库上， 可以通过下面的命令查询 

```
node1 | node2# docker network ls 
```

返回结果:
```
NETWORK ID          NAME                DRIVER              SCOPE
...
1cd9764f1051        web                 calico              global              
...
```

### 在另外节点添加容器

    同样在node2上面部署`container2`, 设置下`container_2`的IP为`192.168.22.2` 命令如下:
```
node2# docker run --net web --name  container_2 --ip 192.168.22.2 -tid centos
```
    然后我们就会发现 container_1| container_2 能够互相 ping 

```
node1 # docker exec web_contianer_1 ping 192.168.22.1
node2 # docker exec web_contianer_1 ping 192.168.22.2
```

两个容器能够互相ping通，所以我们认为他们网络是网络是通的

### 路由的实现原理(参考http://h2ex.com/202，宜信云平台专家)

    接下来让我们看一下在上面的 demo 中，Calico 是如何让不在一个节点上的两个容器互相通讯的:
    
- Calico节点(docker agent)启动后会查询`Etcd`(中心数据库)，和其他 Calico节点使用BGP协议建立连接
```
 node1 # netstat -anpt | grep 179
 tcp	0      0	0.0.0.0:179             0.0.0.0:*               LISTEN      29535/bird
 tcp   0      0	192.168.20.1:53646      192.168.20.2:179        ESTABLISHED 29535/bird
```

- 容器启动的时候，calico作为docker网络的驱动插件对网络进行初始化
- 如果没有指定 IP，则查询 Etcd 自动分配一个可用 IP
- 创建一对veth接口用于容器和主机间通讯，设置好容器内的 IP 后，打开 IP 转发
- 在主机路由表添加指向此接口的路由

- docker主机内部路由表情况
```
 主机上
 node1# ip link show
 ...
 16: cali70ae6262396@if15: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP mode DEFAULT qlen 1000

     link/ether 42:8d:73:32:f5:fe brd ff:ff:ff:ff:ff:ff link-netnsid 0

 容器内:
 web_container_1# ip addr
 ...
 15: cali0@if16: <BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1500 qdisc pfifo_fast state UP qlen 1000

    link/ether ee:ee:ee:ee:ee:ee brd ff:ff:ff:ff:ff:ff

    inet 192.168.22.2/32 scope global cali0

       valid_lft forever preferred_lft forever

    inet6 fe80::ecee:eeff:feee:eeee/64 scope link 

       valid_lft forever preferred_lft forever
 
 node1# ip route
 ...
 192.168.22.2 dev cali70ae6262396  scope link
 ...
```

  当主机收到目的地址为`192.168.22.2`数据包就会自动转发到接口`cali70ae6262396`, 由接口`cali70ae6262396`转发容器接口`cali0@if16`上.

- docker主机之间通过BGP协议广播给其他所有节点，在两个节点上的路由表最终是这样的:
```
 node1# ip route
 ...
 192.168.22.0/26 via 192.168.20.2 dev enp2s0  proto bird 
 192.168.22.1 dev cali70ae6262396  scope link
 blackhole 192.168.22.64/26  proto bird

 node2# ip route
 192.168.22.2 dev calie3b73c467e1  scope link 
 192.168.22.1 via 192.168.20.1 dev enp2s0  proto bird 
 192.168.22.64/26 via 192.168.20.9 dev enp2s0  proto bird 
```

### 配置网络的访问规则

    上文通过命令`docker network create --driver calico --ipam-driver calico --subnet=192.168.22.0/24 web`, 创建`web`网络的同时， calico自动创建对应的网络规则，把规则规则命名为`web`的NETWORK ID

    列举profile命令
```
node1|node2 # calicoctl profile  show
 +------------------------------------------------------------------+
 |                               Name                               |
 +------------------------------------------------------------------+
 | 1cd9764f10510862a4244f9d675cd4c8a73d147136bf13eacdfc188d06fc0e05 |
 +------------------------------------------------------------------+
```

  列举网络命令
```
node1 | node2# docker network ls

    返回结果:
   NETWORK ID          NAME                DRIVER              SCOPE
   ...
   1cd9764f1051        web                 calico              global
  ...
```

   虽然profile是使用NETWORK ID进行命名，但是我们依然可以使用网络名字对策略进行查询，默认情况网络规则如下

```
node1 | node2# calicoctl profile web rule show

 Inbound rules:
    1 allow from tag web
 Outbound rules:
    1 allow
```

   规则意思`web`网络container允许接收来自`web`的cantainer发送过来的网络包, 允许向所有网络发送数据, 包括向container主机发送网络包。

   如果不制定ip地址，IPAM自动分配ip地址， 命令如下
```
node1# docker run --net web --name container -tid centos
```
   注意自动分配，容器停止/重新启动以后，ip地址会产生变化。


## 利用 Profile 实现 ACL

   例如同时创建`web`和`mysqldb`两网络，在默认的情况下，两个网络container是不允许互相访问，需要修改profle. 

   我们需要创建一个docker image 带有nc`网络瑞士军刀`， 进行实验。 Dockerfile 如下
```
FROM centos
ENV LANG en_US.UTF-8

RUN yum install -y nc telnet
```

创建对应的的docker镜像,镜像需要在每个node的节点上创建

```
  node1 | node2 docker build -t calico-net-test:1.0 ./
```

  通过项目复杂例子说明怎么配置Profile 实现 ACL
  在常见的网站架构中，一般是前端 WebServer 将请求反向代理给后端的 APP 服务，服务调用后端的 DB：
```
web -> app -> mysqldb
```
所以我们要实现：

    web: 暴露 80 和 443 端口
    app: 允许 web 访问
    mysqldb: 允许 app访问 3306 端口
    除此之外，禁止所有跨服务访问

### 创建三个网络

   首先通过docker创建web， app， mysqldb, 三个网络, 并且指定三个网络子网(不指定也可以), 命令只需要在
node1或node2其中一台节点执行就可以，目前在node1执行

```
node1# docker network create --driver calico --ipam-driver calico --subnet=192.168.22.0/24 web
node1# docker network create --driver calico --ipam-driver calico --subnet=192.168.23.0/24 mysqldb
node1# docker network create --driver calico --ipam-driver calico --subnet=192.168.24.0/24 app
```
   创建成功后可以通过查询是三个网络是否存在,node1或者node2执行返回结果都是一样的:
```
node1|node2# docker network ls
NETWORK ID          NAME                DRIVER              SCOPE
...
ad15bb272ea5        app                 calico              global              
e87bb4ef80aa        mysqldb             calico              global              
1cd9764f1051        web                 calico              global              
...

所有calico 驱动创建的网络SCOPE都是global

```

### 配置网络的访问权限

- 1. 配置web网络允许外部网络对80, 443端口的访问。需要通过calicoctl对web进行配置，在node1或node2都可以执行

```
node1# calicoctl profile web rule add inbound allow tcp to ports 80,443
node1# calicoctl profile web rule show

Inbound rules:
   1 allow from tag web
   2 allow tcp to ports 80,443
Outbound rules:
   1 allow
``` 

-- 1) 测试效果通过host直接访问容器测试，首先使用host对容器进行访问.

   在node1创建容器名字为:web_container_1, 使用web网络，配置ip地址为192.168.22.1

```
node1# docker run --net web --name web_container_1 --ip 192.168.22.1 -td calico-net-test:1.0
```
  
  在node1机器通过进入容器通过nc打开80端口

```
node1# docker-enter web_container_1
web_container_1# nc -l 80
``` 

  在node2机器连接容器的`web_container_1`的80端口

```
node2# nc 192.168.22.1 80 

可以通过命令行互相发送和接受数据
```  

   在`web_container_1`可以接收到数据， 同样在`web_container_1`打开443端口， node2还是可以连接上去。
但是在`web_container_1`打开80, 443以外端口，都无法连接上去。
  
-- 2) 然后使用mysqldb， app网络的容器访问，profile配置所以网络都可以访问web的80,443端口,但是测试其他
端口都服务访问。

-- 3) 同样可以通过json对web进行更新

   在node1或node2都可以执行更新， 以node1为例
```
node1# cat web-rule.json
{
  "inbound_rules": [
    {
      "action": "allow", 
      "src_tag": "web"
    }, 
    {
      "action": "allow", 
      "protocol": "tcp", 
      "dst_ports": [
        80, 
        443
      ]
    }
  ], 
  "outbound_rules": [
    {
      "action": "allow"
    }
  ]
}

node1# calicoctl profile web rule update < web-rule.json
```

- 2. 配置`app`网络，只允许`web`网络访问所以的端口，其他网络都不允许访问。需要通过`calicoctl`对`app`网络进行配置，
     在node1或node2都可以执行.

```
node1# calicoctl profile app add inbound allow from tag web
```

测试方法

-- 1) 创建一个`app`网络容器app_container_1, ip地址为192.168.23.1， 在node2上，进入容器，通过nc打开任意端口，以9000
      为例子，测试web_container_是否能够和其建立连接和通信命令如下

```
node2机器

node2# docker run --net app --name app_container_1 --ip 192.168.23.1 -td calico-net-test:1.0
node2# docker-enter app_container_1
app_container_1# nc -l 9000

node1机器
node1# docker-enter web_container_1
web_container_1# nc 192.168.23.1 9000

建立连接以后可以通过终端发生字符，在app_container_1端可以看到接收数据，代表网络是通过的。
```

-- 2) 通过其他网络访问，应该无法连接，代表配置正确。

- 3. 创建一个mysqldb网络，配置允许app网络访问它内部虚拟及3306端口。可以在 node1 和 node2 进行配置
```
node1 | node2# calicoctl profile mysqldb rule remove inbound allow tcp from tag app to ports 3306 
```

### Profile 高级特性：Tag
   有同学可能说，在现实环境中，会有多组不同的 APP 都需要访问 DB，如果每个 APP 都在 db 中增加一条规则也很麻烦同时还容易出错。
   这里我们可以利用Profile 的高级特性 Tag 来简化操作:

- 每个 Profile 默认拥有一个和 Profile 名字相同的 Tag
- 每个 Profile 可以有多个 Tag，以 List 形式保存
利用 Tag 我们可以将一条规则适配到指定的一组 Profile 上。

参照上面的例子，我们给所有需要访问 DB 的 APP 的 Profile 都加上 db-users这个Tag, 步骤如下

- Tag: db-users 相当于docker 一个network 

```
node1 | node2 # docker network create --driver calico --ipam-driver calico db-users
```

- 然后删除db-users inbound 选项，因为他只作tag用，无需其他允许

```
node1 | node2 # calicoctl profile db_users rule remove inbound allow from tag db_users
```

- 将之前的 src_tag: app 替换为 src_tag: db-users。这样所有打了 db-user 这个 Tag 的实例就都能访问数据库了:
```
{
  "inbound_rules": [
    {
      "action": "allow", 
      "src_tag": "mysqldb"
    }, 
    {
      "action": "allow", 
	  "src_tag": "db-users",
      "protocol": "tcp", 
      "dst_ports": [
        3306
      ]
    }
  ], 
  "outbound_rules": [
    {
      "action": "allow"
    }
  ]
}

node1# calicoctl profile mysqldb rule update < mysqldb-rule.json
```

## 配置BGP Route Reflector

   上面我们是使用calico 是使用BGP "full node-to-node mesh", calico节点自动在etcd数据库获取节点信息，自动创建和其他calico-node建立BGP peer。
   这种模型只适合小规模的部署或者所有的Calico-node都在一个网段上。
   现在屏蔽"full node-to-node mesh"方式，创建`Route Reflector`，所以的Calico-node 只需要和`Route Reflector`连接。


   例如环境如下:

   192.168.20.1 node1
   192.168.20.2 node2
   192.168.20.3 node3

   192.168.20.4 route_reflector


- 1. 关闭"full node-to-node mesh" 模式
```
node1# calicoctl bgp node-mesh off
```  

- 2. 运行BIRD Route Reflector on node1 

```
node1# docker run --privileged --net=host -d -e IP=192.168.20.1 -e ETCD_AUTHORITY=192.168.20.1:2379 -v /var/log/:/var/log/ calico/routereflector:latest
```

- 3. 添加Route Reflector到etcd数据库
```
curl -L http://192.168.20.1:2379/v2/keys/calico/bgp/v1/rr_v4/192.168.20.4 -XPUT -d value="{\"ip\":\"192.168.20.4\",\"cluster_id\":\"1.0.0.1\"}"
```

- 4. 每个节点通过calicoctl配置Route Reflectors

-- 1) 获取节点as号(每个节点都一样)
```
#calicoctl bgp default-node-as
64511 
``` 
    不同环境返回as num 都不一样，根据这个as num配置第二步。

-- 2) 在所有calico-node上添加BGP peer 
```
calicoctl bgp peer add 192.168.20.4 as 64511
calicoctl bgp peer show
```


- [集成到mesos marathon 集群](mesos-marathon/README.md)
- [配置私有仓库registry](registry/README.md)
- [配置VMWare harbor](harbor/README.md)
