### 1.1 生成512MB块文件
  通过uuidgen生成随机块文件名称
```
$ uuidgen 
5633f39c-0733-4558-bc93-a70423765c8b

$truncate --size=512M /pv-data/5633f39c-0733-4558-bc93-a70423765c8b.img 
```

### 1.2 格式化块文件
  下面是把块文件格式化为ext4格式例子
```
$ mkfs.xfs -q /pv-data/5633f39c-0733-4558-bc93-a70423765c8b.img

```

### 1.3 挂载文件块
  把文件块挂载挂载到指定目录
```
$ mkdir -p /pv-data/5633f39c-0733-4558-bc93-a70423765c8b
$ mount 5633f39c-0733-4558-bc93-a70423765c8b.img 5633f39c-0733-4558-bc93-a70423765c8b
```

### 1.4 注册到PV上
    把目录注册到k8s PV. 例如这个虚拟文件块在k8s-3机器上， 大小512M, 挂在目录/pv-data/5633f39c-0733-4558-bc93-a70423765c8b

```
apiVersion: v1
kind: PersistentVolume
metadata:
  name: 5633f39c-0733-4558-bc93-a70423765c8b
  label: 
  annotations:
    volume.alpha.kubernetes.io/node-affinity: >
      {
         "requiredDuringSchedulingIgnoredDuringExecution": {
           "nodeSelectorTerms": [
            { "matchExpressions": [
               { "key": "kubernetes.io/hostname",
                 "operator": "In",
                 "values": ["k8s-3"]
               }
           ]}
         ]}
      }
spec:
  capacity:
    storage: 512Mi
  accessModes:
  - ReadWriteOnce
  storageClassName: local-storage
  local:
    path: /pv-data/5633f39c-0733-4558-bc93-a70423765c8b
```

```

### 1.4 扩展文件块
  如果用户需要扩展文件块到1G, 需要用户停止应用.
```
$ umount  /pv-data/5633f39c-0733-4558-bc93-a70423765c8b
$ truncate --size=1024M /pv-data/5633f39c-0733-4558-bc93-a70423765c8b.img
$ mount /pv-data/5633f39c-0733-4558-bc93-a70423765c8b.img /pv-data/5633f39c-0733-4558-bc93-a70423765c8b
$ xfs_growfs /pv-data/5633f39c-0733-4558-bc93-a70423765c8b 
```

### 1.5 同步更新PV和PVC
