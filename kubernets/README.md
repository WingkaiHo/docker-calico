## 环境描述
### 操作系统
    centos7.1

### 集群环境
    物理机器表格
    | 机器名    | IP             | 角色
    | host223   | 192.168.10.223 | master, node
    | host224   | 192.168.10.224 | node 

## 1.kubernets 集群初始化安装

### 1.1 下载原代码
```
	git clone https://github.com/kubernetes/kubernetes.git
```

### 1.2 输入集群基本信息

### 1.2.1 设置环境变量
	设置环境变量,kube release版本可以在`https://github.com/kubernetes/kubernetes/releases`参看
```
export KUBE_VERSION=v1.4.6
export FLANNEL_VERSION=0.5.5
export ETCD_VERSION=1.1.8
```

### 1.2.2 配置集群信息
    进入源码的目录以后修改./cluster/centos/config-default.sh文件

```
指定master机器ip地址
export MASTER=${MASTER:-"root@192.168.20.211"}

输入集群所有节点ip地址
export NODES=${NODES:-"root@192.168.10.223 root@192.168.10.224"}
配置节点书目
export NUM_NODES=${NUM_NODES:-2}

配置 SERVICE_CLUSTER_IP_RANGE 
export SERVICE_CLUSTER_IP_RANGE=${SERVICE_CLUSTER_IP_RANGE:-"192.168.21.0/24"}

配置 overlay 网络ip range
export FLANNEL_NET=${FLANNEL_NET:-"172.20.0.0/16"}

修改docker 参数, 使用daocloud加速下载
export DOCKER_OPTS=${DOCKER_OPTS:-"--cluster-store=etcd://$MASTER_IP:2379, --registry-mirror=http://1a653205.m.daocloud.io --dns=192.168.21.2"}
```

### 1.2.3 启动自动化部署集群

```
KUBERNETES_PROVIDER=centos ./kube-up.sh
```

### 1.2.4 部署kubelet dns服务
	由于dns自动化部署在centos7没有的, 只能ubuntu脚本使用.例如kubenets项目的目录/root/kubernetes/, kubernets DNS ip 是192.168.21.2, ip必须在SERVICE_CLUSTER_IP_RANGE里面. 执行之前最好可以把对应镜像下载下来. 

```
export DNS_DOMAIN=cluster.local
export DNS_SERVER_IP=192.168.21.2 
sed -e "s/\\\$DNS_DOMAIN/${DNS_DOMAIN}/g" "${KUBE_ROOT}/cluster/addons/dns/skydns-rc.yaml.sed" > skydns-rc.yaml
sed -e "s/\\\$DNS_SERVER_IP/${DNS_SERVER_IP}/g" "${KUBE_ROOT}/cluster/addons/dns/skydns-svc.yaml.sed" > skydns-svc.yaml

kuberlet create -f skydns-rc.yaml
kuberlet create -f skydns-svc.yaml
```

    各个节点kubelet 启动参数加入cluster dns. /opt/kubernetes/cfg/kubelet

```
KUBELET_ARGS="--cluster-dns=192.168.21.2 --cluster-domain=cluster.local"
```

### 1.2.4 部署dashborad

    由于kubernetes部署需要用到下面的镜像,建议在加载到各个节点上: gcr.io/google_containers/pause-amd64
