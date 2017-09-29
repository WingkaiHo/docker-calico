### 本地存储

    使用本地存储注意地方，本地存储需要和机器绑定，否则应用出问题，Pod被重新启动以后，应用被调度到其他机器之前数据就会丢失。在Deployment的时候使用大量NodeSelector就失去k8s调度的意义，本文使用PV和PVC实现本地存储机器绑定， 防止调度而导致Pod状态丢失


### 创建local storage PV

   - local volume是k8s v1.7 ~ v1.8 Alpha特性，需要用户打开才能使用， 需要在启动kube-apiserver, kube-controller-manager, kube-scheduler 的时候添加参数"--feature-gates=AllAlpha=true", 否则执行下面yaml 的时候会报错 

```
/opt/kubernetes/bin/kube-controller-manager --logtostderr=true --v=4 --master=192.168.165.212:8080 --root-ca-file=/srv/kubernetes/ca.crt --service-account-private-key-file=/srv/kubernetes/server.key --leader-elect --feature-gates=AllAlpha=true

/opt/kubernetes/bin/kube-apiserver --logtostderr=true --v=4 --etcd-servers=https://192.168.165.212:2379,https://192.168.165.213:2379,https://192.168.165.214:2379 --etcd-cafile=/srv/kubernetes/etcd/ca.pem --etcd-certfile=/srv/kubernetes/etcd/client.pem --etcd-keyfile=/srv/kubernetes/etcd/client-key.pem --insecure-bind-address=0.0.0.0 --insecure-port=8080 --kubelet-port=10250 --advertise-address=192.168.165.212 --allow-privileged=false --service-cluster-ip-range=173.18.3.0/24 --admission-control=Initializers,NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultTolerationSeconds,ResourceQuota --client-ca-file=/srv/kubernetes/ca.crt --tls-cert-file=/srv/kubernetes/server.cert --tls-private-key-file=/srv/kubernetes/server.key --feature-gates=AllAlpha=true

/opt/kubernetes/bin/kube-scheduler --logtostderr=true --v=4 --master=192.168.165.212:8080 --leader-elect  --feature-gates=AllAlpha=true
``` 

  - 编辑持久化PV, 名字为edd33f70-c8b5-4d4b-8e0d-e19def797ee0， 存放到机器"192.168.165.212", 存放路径是: "/root/k8s-local-pv/edd33f70-c8b5-4d4b-8e0d-e19def797ee0"

```
apiVersion: v1
kind: PersistentVolume
metadata:
  name: edd33f70-c8b5-4d4b-8e0d-e19def797ee0
  annotations:
    volume.alpha.kubernetes.io/node-affinity: >
      {
         "requiredDuringSchedulingIgnoredDuringExecution": {
           "nodeSelectorTerms": [
            { "matchExpressions": [
               { "key": "kubernetes.io/hostname",
                 "operator": "In",
                 "values": ["192.168.165.212"]
               }
           ]}
         ]}
      }
spec:
  capacity:
    storage: 20Gi
  accessModes:
  - ReadWriteOnce
  storageClassName: local-storage
  local:
    path: /root/k8s-local-pv/edd33f70-c8b5-4d4b-8e0d-e19def797ee0
```
  local volume 和 hostPath 还是有区别，hostPath不支持选择机器。hostPath使用如果路径不存在，由机器帮你创建， local volme使用的时候如果路径不存在，就会报错。

  - 应用PVC， 需要填写要求存储容量， 以及存储类型， `storageClassName: local-storage`

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pv-claim
  labels:
    app: wordpress
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: local-storage
```
   这个PVC与PV没有直接联系的，k8s集群会按照PVC要求选择适合PV, 分配给PVC使用。

  - Deployment 怎么通过使用PVC
```
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: wordpress-mysql
  labels:
    app: wordpress
spec:
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: wordpress
        tier: mysql
    spec:
      containers:
      - image: 172.18.2.103/wordpress/mysql:latest
        name: mysql
        env:
          # $ kubectl create secret generic mysql-pass --from-file=password.txt
          # make sure password.txt does not have a trailing newline
        - name: MYSQL_ROOT_PASSWORD
          value: wordpress
        ports:
        - containerPort: 3306
          name: mysql
        volumeMounts:
        - name: mysql-persistent-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-persistent-storage
        persistentVolumeClaim:
          claimName: mysql-pv-claim
```
  claimName 必须和PersistentVolumeClaim定义名称相同。

### 创建Deploymnet

   通过kubectl 创建PV，mysql应用
```
$kubectl create -f pv.yml
$kubectl create -f mysql-deployment.yaml
```

   可以测试把Pod kill掉， 把实例配置为0停止， 配置为1重新启动， 发现mysql都保持在`192.168.165.212` 上。
