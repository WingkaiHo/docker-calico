## 1. 给mysql数据库创建RBD持久化存储

### 1.1.1 创建rbd镜像
    例如下面创建的是100GB镜像,名为redis-volume
```
rbd create wordpress-mysql --size 100G
```

### 1.1.2 把镜像格式化为xfs文件系 

   加载rbd驱动模块, 注意如果格式ext4,挂载后自动出现lost-found目录,导致mysql的需要空目录初始化程序无法使用.
```
modprobe rbd
lsmod | grep rbd
```

  把rbd映射到block device
```
rbd map rbd/wordpress-mysql

如果系统返回
rbd: sysfs write failed
rbd: map failed: (6) No such device or address

需要执行下面命令:
rbd feature disable wordpress-mysql  exclusive-lock object-map fast-diff deep-flatten

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

### 1.1.3 创建挂载rbd的用户的secret
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

### 1.2 创建mysql kubernetes实例 

### 1.2.1 mysql 使用rbd volume

    mysql 持久化目录/var/lib/mysql 目录, 使用bind mount把rbd volume 挂到此目录. 描述文件wordpress.yml

```
kind: ReplicationController
apiVersion: v1
metadata:
  name: wordpress-mysql
  labels:
    name: wordpress-mysql
spec:
  replicas: 1
  selector:
    name: wordpress-mysql
  template:
    metadata:
      labels:
        name: wordpress-mysql
    spec:
      containers:
      - name: wordpress-mysql
        image: mysql:5.7
        imagePullPolicy: IfNotPresent
        env:
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
        rbd:
          monitors:
             - 192.168.10.223:6789
          pool: rbd
          image: wordpress-mysql
          user: admin
          secretRef:
            name: ceph-client-admin-keyring
          fsType: xfs
          readOnly: false
```

    启动mysql实例:
```
    kubectl --namespece default create -f wordpress-mysql-rc.yml
```

1.2.2 创建mysql服务

 创建mysql服务, 服务只提供wordpress,没用使用端口映射的方式.
```
kind: Service
apiVersion: v1
metadata:
  name: wordpress-mysql
  labels:
    name: wordpress-mysql
spec:
  ports:
    - port: 3306
      targetPort: 3306
  selector:
    name: wordpress-mysql 
```

    启动mysql service:
```
    kubectl --namespece default create -f wordpress-mysql-sv.yml
```

1.3.1 创建wordpress
```
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  ports:
    - port: 80
  selector:
    app: wordpress
    tier: frontend
  type: LoadBalancer
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: wordpress
        tier: frontend
    spec:
      containers:
      - image: wordpress:latest
        name: wordpress
        env:
        - name: WORDPRESS_DB_HOST
          value: wordpress-mysql.default.svc.cluster.local.:3306
        - name: WORDPRESS_DB_PASSWORD
          value: wordpress
        ports:
        - containerPort: 80
          name: wordpress
```

       其中wordpress-mysql.default.svc.cluster.local是mysql 在kubenetes dns地址, 容器内部通kube-dns 服务器解析对应mysql pod ip地址.

