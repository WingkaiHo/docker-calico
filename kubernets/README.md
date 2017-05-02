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

   kubnernetes 镜像存放在gcr.io, 如果不能翻墙可以在`docker hub`上在, https://hub.docker.com/r/googlecontainer/

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
export DOCKER_OPTS=${DOCKER_OPTS:-"--cluster-store=etcd://$MASTER_IP:2379, --registry-mirror=http://1a653205.m.daocloud.io"}
```

### 1.2.3 启动自动化部署集群

```
KUBERNETES_PROVIDER=centos ./kube-up.sh
```

#### 1.2.3.1 修改etcd启动项目

```
  #vim /opt/kubernetes/cfg/etcd
  
  ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
  ETCD_ADVERTISE_CLIENT_URLS="http://192.168.10.223:2379" 
```
  `ETCD_ADVERTISE_CLIENT_URLS` 需要填写etcd具体ip地址,否者客户端使用此地址进行连接的时候连不上.
### 1.2.4 部署kubelet dns服务
	由于dns自动化部署在centos7没有的, 只能ubuntu脚本使用.例如kubenets项目的目录/root/kubernetes/, kubernets DNS ip 是192.168.21.2, ip必须在SERVICE_CLUSTER_IP_RANGE里面. 执行之前最好可以把对应镜像下载下来. 

```
export DNS_DOMAIN=cluster.local
export DNS_SERVER_IP=192.168.21.2 
sed -e "s/\\\$DNS_DOMAIN/${DNS_DOMAIN}/g" "${KUBE_ROOT}/cluster/addons/dns/skydns-rc.yaml.sed" > skydns-rc.yaml
sed -e "s/\\\$DNS_SERVER_IP/${DNS_SERVER_IP}/g" "${KUBE_ROOT}/cluster/addons/dns/skydns-svc.yaml.sed" > skydns-svc.yaml
```

   在skydns-rc.yaml 添加kubernete master url

```
- name: kubedns
        image: gcr.io/google_containers/kubedns-amd64:1.8
...
- --domain=cluster.local.
- --dns-port=10053
- --kube-master-url=http://192.168.20.211:8080
...
```

```
kuberlet create -f skydns-rc.yaml
kuberlet create -f skydns-svc.yaml
```

    各个节点kubelet 启动参数加入cluster dns. /opt/kubernetes/cfg/kubelet

```
KUBELET_ARGS="--cluster-dns=192.168.21.2"
```

### 1.2.4 部署dashborad

    由于kubernetes部署需要用到下面的镜像,建议在加载到各个节点上: gcr.io/google_containers/pause-amd64


## 2 kubernets 使用Ceph做后端存储

### 2.1 使用ceph rbd做后端存储

### 2.1.1 创建rbd镜像
    例如下面创建的是100GB镜像,名为redis-volume
```
rbd create redis-volume --size 100G
```

### 2.1.2 把镜像格式化为xfs文件系 

   加载rbd驱动模块, 注意如果格式ext4,挂载后自动出现lost-found目录,导致mysql的需要空目录初始化程序无法使用.
```
modprobe rbd
lsmod | grep rbd
```

  把rbd映射到block device
```
rbd map rbd/redis-volume

如果系统返回
rbd: sysfs write failed
rbd: map failed: (6) No such device or address

需要执行下面命令:
rbd feature disable redis-volume  exclusive-lock object-map fast-diff deep-flatten

重新映射
rbd map rbd/redis-volume

检查是否成功
rbd showmapped
id pool image		   snap device
0  rbd  redis-volume   -    /dev/rbd0
```

格式化设备

```
mkfs.xfs /dev/rbd0 
rbd unmap /dev/rbd0
```

### 2.1.3 创建挂载rbd的用户的secret
    在客户端进行rbd挂载时需要进行用户认证，采用用户名和其keyring。默认使用ceph-deploy部署创建一个admin用户，对应keyring为/etc/ceph/ceph.client.admin.keyring 将keyring里面的值用base64进行编码

```
	# awk '/key/{print $3}' /etc/ceph/ceph.client.admin.keyring  | base64
QVFCWll0MVZvRddf5R2hBQUlzMm92VGMvdmMyaFzaWjl2dFhsS1E9PQo=
```

   编写ceph-secret.yml 文件

```
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: ceph-client-admin-keyring
data:
  key: QVFCWll0MVZvRddf5R2hBQUlzMm92VGMvdmMyaFzaWjl2dFhsS1E9PQo=
```

   在kubenetes 对应的命名空间加载

```
kubectl --namespace default create -f ceph-secret.yml
``` 


### 2.1.4 创建pod并且将刚才已经格式化的img挂载到container中

    例子是把rbd的镜像挂载到容器的/mnt, 

    redis.yml

```
apiVersion: v1
kind: Pod
metadata:
  name: test-rbd
spec:
  containers:
  - name: nginx
    image: nginx
    volumeMounts:
    - name: rbd
      mountPath: /mnt
  volumes:
  - name: rbd
    rbd:
      monitors:
      - 192.168.10.123:6789
      pool: rbd
      image: redis-volume
      user: admin
      secretRef:
        name: ceph-client-admin-keyring
      fsType: xfs
```


```
kubectl --namespace default create -f redis.yml
``` 

   namespace需要和ceph-client-admin-keyring一致, 否者无法获取到secret.


### 2.2 kubernets 添加监控平台

#### 2.2.1 heapster controller的定义文件如下:

```
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: heapster-v1.2.0
  namespace: kube-system
  labels:
    k8s-app: heapster
    kubernetes.io/cluster-service: "true"
    version: v1.2.0
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: heapster
      version: v1.2.0
  template:
    metadata:
      labels:
        k8s-app: heapster
        version: v1.2.0
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ''
        scheduler.alpha.kubernetes.io/tolerations:
'[{"key":"CriticalAddonsOnly", "operator":"Exists"}]'
    spec:
      containers:
        - image: gcr.io/google_containers/heapster:v1.2.0
          name: heapster
          livenessProbe:
            httpGet:
              path: /healthz
            - --source=kubernetes:http://192.168.10.223:8080?inClusterConfig=false&useServiceAccount=true&auth=
            - --sink="graphite:tcp://graphite.kube-system.svc.cluster.local:2003?prefix=kubernetes."
        - image: gcr.io/google_containers/addon-resizer:1.6
          name: heapster-nanny
          resources:
            limits:
              cpu: 50m
              memory: 92160Ki
            requests:
              cpu: 50m
              memory: 92160Ki
          env:
            - name: MY_POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: MY_POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
          command:
            - /pod_nanny
            - --cpu=80m
            - --extra-cpu=0.5m
            - --memory=140Mi
            - --extra-memory=4Mi
            - --threshold=5
            - --deployment=heapster-v1.2.0
            - --container=heapster
            - --container=heapster
            - --poll-period=300000
            - --estimator=exponential
```

### 2.2.2 heapster-service的定义文件如下:

```
kind: Service
apiVersion: v1
metadata:
  name: heapster
  namespace: kube-system
  labels:
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: "Heapster"
spec:
  ports:
    - port: 80
      targetPort: 8082
  selector:
    k8s-app: heapster
```


### 2.2.3创建controller及暴露服务:

```
$ kubectl create -f heapster-controller.yaml
$ kubectl create -f heapster-service.yaml
```
查看集群信息:

```
$ kubectl cluster-info
Kubernetes master is running at https://192.168.10.223
Heapster is running at
https://192.168.10.223/api/v1/proxy/namespaces/kube-system/services/heapster
KubeDNS is running at
https://192.168.10.223/api/v1/proxy/namespaces/kube-system/services/kube-dns
```
可以看到Heapster已经启动，而在kubernetes dashboard上此刻就可以看到监控信息了.



## 3 kubernetes use calico

### 3.1 Download calico kubernetes yaml file

```
   wget http://docs.projectcalico.org/v2.0/getting-started/kubernetes/installation/hosted/calico.yaml
```
  
   1) 配置`etcd_endpoints` ip地址和你集群ip地址一致
   2) 配置 ip地址池适应你的环境 (不要于kubernetes service ip 地址段冲突)
```
    ippool.yaml: |
      apiVersion: v1
      kind: ipPool
      metadata:
        cidr: 192.168.24.0/24
      spec:
        nat-outgoing: true
```

### 3.2 Apply calico yaml file

    修改完毕calico以后, 最好先下载好对应的镜像以后才执行下面命令

```
# kuberctl apply -f calico.yaml
```

    执行以后kubernetes cluster每个节点都会有`calico/cni:v1.5.6` 和  `quay.io/calico/node:v1.0.2` 两个镜像对应的容器.

    `calico/cni:v1.5.6` 给host生成和配置cni对应文件,文件存放到目录`/etc/cni/net.d`, 把`calico`和`calico-ipam`拷贝到目录`/opt/cni/bin`
```
# ll /etc/cni/net.d
-rw-r--r--. 1 root root 1331 Feb  6 08:20 10-calico.conf
-rw-r--r--. 1 root root  275 Feb  6 08:20 calico-kubeconfig
drwxr-xr-x. 2 root root 4096 Nov 28 09:38 calico-tls

# ll /opt/cni/bin/
...
-rwxr-xr-x. 1 root root 27585856 Feb  6 08:20 calico
-rwxr-xr-x. 1 root root 27058592 Feb  6 08:20 calico-ipam
...
```

    `quay.io/calico/node:v1.0.2` 是calico节点容器, 负责从etcd获取新节点信息,配置路由规则.

    网络安全规则是通过`calico/kube-policy-controller:v0.5.2` 容器进行配置

### 3.2 更新kubelet 服务的参数
   
    由于calico文档只有在手工配置的时候才提示需要修改更新kubelet启动参数, 这个自动安装以后也需要. 文档没有说明, 很多时候都会走弯路.

    修改启动kuberlet的service文件, `KUBELET_ARGS` 不支持同时写入多个参数
```
  vim /usr/lib/systemd/system/kubelet.service

ExecStart=/opt/kubernetes/bin/kubelet $KUBE_LOGTOSTDERR  $KUBE_LOG_LEVEL $NODE_ADDRESS $NODE_PORT $NODE_HOSTNAME $KUBELET_API_SERVER $KUBE_ALLOW_PRIV $KUBELET_ARGS  
```

    修改启动参数
```
    vim /opt/kubernetes-1.5/cfg/kubelet
    KUBELET_ARGS=--cluster-dns=192.168.10.223  --cluster-domain=cluster.local --network-plugin=cni --cni-bin-dir=/opt/cni/bin --cni-conf-dir=/etc/cni/net.d
```

    修改以后需要重新启动kuberlet服务.

### 3.3 测试calico network policy 功能

#### 3.3.1 创建新的namespace

```
    kubectl create ns advanced-policy-demo 
```

#### 3.3.2 配置namespace为isolation模式

```
   kubectl annotate ns advanced-policy-demo "net.beta.kubernetes.io/network-policy={\"ingress\":{\"isolation\":\"DefaultDeny\"}}"
```

#### 3.3.3 运行nginx服务

    在advanced-policy-demo命名空间创建nginx服务
```
    kubectl run --namespace=advanced-policy-demo nginx --replicas=2 --image=nginx
    kubectl expose --namespace=advanced-policy-demo deployment nginx --port=80
```

#### 3.3.4 检查对应名字空间profile
 
    列举所有名字空间profile
```
$ calicoctl get profile -o wide
NAME                          TAGS                          
k8s_ns.advanced-policy-demo   k8s_ns.advanced-policy-demo   
k8s_ns.ceph                   k8s_ns.ceph                   
k8s_ns.default                k8s_ns.default                
k8s_ns.kube-system            k8s_ns.kube-system            
```

   获取`k8s_ns.advanced-policy-demo`的具体规则

```
$ calicoctl get profile k8s_ns.advanced-policy-demo -o yaml
- apiVersion: v1
  kind: profile
  metadata:
    name: k8s_ns.advanced-policy-demo
    tags:
    - k8s_ns.advanced-policy-demo
  spec:
    egress:
    - action: allow
      destination: {}
      source: {}
    ingress:
    - action: deny
      destination: {}
      source: {}
```
  从上面规则可以看到禁止所有外面的访问这个命名空间所有容器.

### 3.3.5 查询calico workloadendpoint(由calico分配ip的容器)
```
$ calicoctl get workloadendpoint
NODE      ORCHESTRATOR   WORKLOAD                                            NAME   
host223   k8s            advanced-policy-demo.nginx-701339712-zj8f5          eth0   
host224   k8s            advanced-policy-demo.nginx-701339712-2sd55          eth0   
host224   k8s            default.jenkins-vjcjs                               eth0   
host224   k8s            default.wordpress-1631525315-2zs7s                  eth0   
host224   k8s            default.wordpress-mysql-em1sz                       eth0   
host224   k8s            kube-system.graphite-xdctq                          eth0   
host224   k8s            kube-system.kubernetes-dashboard-3389493412-qjhcd   eth0   
```
  如果不能一个实例都没有就是calico没有配置好. 查看3.2节步骤是否做好.

  下面是获取某个实例的信息:
```
  $ calicoctl get wep --workload advanced-policy-demo.nginx-701339712-zj8f5 -o yaml

  - apiVersion: v1
  kind: workloadEndpoint
  metadata:
    labels:
      calico/k8s_ns: advanced-policy-demo
      pod-template-hash: "701339712"
      run: nginx
    name: eth0
    node: k8s-node-01
    orchestrator: k8s
    workload: advanced-policy-demo.nginx-701339712-x1uqe
  spec:
    interfaceName: cali347609b8bd7
    ipNetworks:
    - 192.168.44.65/32
    mac: 56:b5:54:be:b2:a2
    profiles:
    - k8s_ns.advanced-policy-demo
``` 

### 3.3.6 测试nginx是否被禁止访问
```
$ kubectl run --namespace=advanced-policy-demo access --rm -ti --image busybox /bin/sh
Waiting for pod advanced-policy-demo/access-472357175-y0m47 to be running, status is Pending, pod ready: false

If you don't see a command prompt, try pressing enter.

/ # wget -q --timeout=5 nginx -O -
wget: download timed out
/ #
```

### 3.3.7 Define Kubernetes policy

   定义网络策略可以允许其他容器访问nginx
```
$ kubectl create -f - <<EOF
kind: NetworkPolicy
apiVersion: extensions/v1beta1
metadata:
  name: access-nginx
  namespace: advanced-policy-demo
spec:
  podSelector:
    matchLabels:
      run: nginx
  ingress:
    - from:
      - podSelector:
          matchLabels: {}
EOF
```

  重新查看网络策略

```
$ calicoctl get policy -o wide
NAME                                ORDER   SELECTOR
advanced-policy-demo.access-nginx   1000    calico/k8s_ns == 'advanced-policy-demo' && run == 'nginx'
k8s-policy-no-match                 2000    has(calico/k8s_ns)
```

  配置以后可以被访问了.

```
$ kubectl run --namespace=advanced-policy-demo access --rm -ti --image busybox /bin/sh
Waiting for pod advanced-policy-demo/access-472357175-y0m47 to be running, status is Pending, pod ready: false

If you don't see a command prompt, try pressing enter.

$ wget -q --timeout=5 nginx -O -
...
```
- [kubernetes monitoring: heapster+graphite+grafana](cluster-monitoring/README.md)
