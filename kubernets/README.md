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
KUBELET_ARGS="--cluster-dns=192.168.21.2 --cluster-domain=cluster.local"
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
####2.2.2 heapster-service的定义文件如下:

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
创建controller及暴露服务:

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

- [kubernetes monitoring: heapster+graphite+grafana](registry/README.md)
