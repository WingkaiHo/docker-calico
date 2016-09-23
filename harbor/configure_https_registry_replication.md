##0. 环境描述
   有两个远程的harbor仓库分别是10.0.0.1， 11.0.0.1, 他们分别使用https协议，进行image 同步。


## 1. Replicating images 配置

### 1.1 新建目标
   进入配置页面`https://10.0.0.1/admin_option#/destinations`, 点击`新建目标` 按要求输入:

```
名称: 11.0.0.1
目标URL: https//11.0.0.1
用户名: admin
密码: Harbor12345
```

### 1.2 添加项目备份目标
    进入配置页面`http://10.0.0.1/project`, 点击其中一个项目, 例如`library`， 再点击`复制`， 然后点击`新增策略`，按照要求输入
```
一般设置：
名称: replication 11.0.0.1
描述: replication 11.0.0.1

目标设置：
名称: 11.0.0.1
目标URL: https//11.0.0.1
用户名: admin
密码: Harbor12345
```
  点击确认

### 1.3 配置Https ca证书
   镜像的同步任务是在容器`deploy_jobservice_1`工作的，所以需要在这个容器里面配置`11.0.0.1` 配置https的CA认证证书。

```
10.0.0.1# docker ps
CONTAINER ID        IMAGE                           COMMAND                  CREATED             STATUS         PORTS	Name
...
01a8df14ce48        deploy_jobservice               "/go/bin/harbor_jobse"   2 days ago          Up 6 hours				deploy_proxy_1
...

10.0.0.1# docker cp 11.0.0.1.crt 01a8df14ce48:/usr/local/share/ca-certificates/11.0.0.1.crt
10.0.0.1# docker-enter 01a8df14ce48 
01a8df14ce48# update-ca-certificates
01a8df14ce48# exit
10.0.0.1# docker stop 01a8df14ce48
10.0.0.1# docker start 01a8df14ce48
```

   配置以后deploy_jobservice容器harbor_jobse可以访问`11.0.0.1`的registery 
