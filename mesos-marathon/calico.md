##1 IPAM

##1.1 添加ip pool

###1.1.1 编辑ip pool 文件
```
$vim ip-pool.yml
apiVersion: v1
kind: ipPool
metadata:
  cidr: 172.16.10.0/24
``` 

###1.1.2 添加网段
```
calicoctl create -f ip-pool.yml 
```

###1.1.2 删除网段

```
calicoctl delete -f ip-pool.yml
```

###1.1.3 获取node 状态
```
calicoctl node status
```
