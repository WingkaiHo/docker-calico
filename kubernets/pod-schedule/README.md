### kubernetes pod 调度
  除了让 kubernetes 集群调度器自动为 pod 资源选择某个节点（默认调度考虑的是资源足够，并且 load 尽量平均），有些情况我们希望能更多地控制 pod 应该如何调度。比如，集群中有些机器的配置更好（SSD，更好的内存等），例如我环境通过label把机器分成不同集群组，测试，准生产，生产，通过k8sd调度到不同机器组。我们希望比较核心的服务（比如说数据库）运行在上面；或者某两个服务的网络传输很频繁，我们希望它们最好在同一台机器上，或者同一个机房。


### node
kubernetes 中有很多对 label 的使用，node 就是其中一例。label 可以让用户非常灵活地管理集群中的资源，service 选择 pod 就用到了 label。这篇文章介绍到的调度也是如此，可以根据节点的各种不同的特性添加 label，然后在调度的时候选择特定 label 的节点。

 在使用这种方法之前，需要先给 node 加上 label，通过 kubectl 非常容易做
```
$kubectl label nodes <node-name> <label-key>=<label-value>

例如
$kubectl label nodes 192.168.165.1 cluster=cluster1
$kubectl label nodes 192.168.165.2 cluster=cluster1
$kubectl label nodes 192.168.165.3 cluster=cluster1


$kubectl label nodes 192.168.165.4 cluster=cluster2
$kubectl label nodes 192.168.165.5 cluster=cluster2
$kubectl label nodes 192.168.165.6 cluster=cluster2
```

添加上 node 选择信息，就变成了下面这样：

apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx
    imagePullPolicy: IfNotPresent
  nodeSelector:
    cluster: cluster1

这个例子就是告诉 kubernetes 调度的时候把 pod 放到有 SSD 磁盘的机器上。

除了自己定义的 label 之外，kubernetes 还会自动给集群中的节点添加一些 label，比如：

- kubernetes.io/hostname：节点的 hostname 名称
- beta.kubernetes.io/os： 节点安装的操作系统
- beta.kubernetes.io/arch：节点的架构类型
......

 不同版本添加的**label**会有不同，这些**label**和手动添加的没有区别，可以通过`--show-labels`查看，也能够用在**nodeSelector**中。

### Pod affinity
  通过上一部分内容的介绍，我们知道怎么在调度的时候让**pod**灵活地选择**node**；但有些时候我们希望调度能够考虑**pod**之间的关系，而不只是**pod-node**的关系 **pod affinity**是在 kubernetes1.4 版本引入的，目前在 1.6 版本也是 beta 功能。

  为什么有这样的需求呢？举个例子，我们系统服务 **A** 和服务**B** 尽量部署在同个主机、机房、城市，因为它们网络沟通比较多；再比如，我们系统数据服务**C**和数据服务**D**尽量分开，因为如果它们分配到一起，然后主机或者机房出了问题，会导致应用完全不可用，如果它们是分开的，应用虽然有影响，但还是可用的。

  **pod affinity** 可以这样理解：调度的时候选择（或者不选择）这样的节点 N ，这些节点上已经运行了满足条件 X。条件 X 是一组 label 选择器，它必须指明作用的 namespace（也可以作用于所有的 namespace），因为 pod 是运行在某个 namespace 中的。

和 **node affinity** 相似，**pod affinity** 也有 `requiredDuringSchedulingIgnoredDuringExecution` 和 `preferredDuringSchedulingIgnoredDuringExecution`，意义也和之前一样。如果有使用亲和性，在 affinity 下面添加 podAffinity 字段，如果要使用互斥性，在 affinity 下面添加 podAntiAffinity 字段。
```
apiVersion: v1
kind: Pod
metadata:
  name: with-pod-affinity
spec:
  affinity:
    # 在failure-domain.beta.kubernetes.io/zone 内和pod 存在标签security=S1亲和
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: security
            operator: In
            values:
            - S1
        topologyKey: failure-domain.beta.kubernetes.io/zone
    podAntiAffinity:
      # 在同一台主机内和存在标签“security=s2”互斥
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: security
              operator: In
              values:
              - S2
          topologyKey: kubernetes.io/hostname
  containers:
  - name: with-pod-affinity
    image: gcr.io/google_containers/pause:2.0
```

- 例如某个应用为了安全起建，应用在每台节点机器只有一个实例
```
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: app1-service3
  labels:
    dcos-service: app1-service3
    dcos-app: app1             
spec:
  replicas: 4 # tells deployment to run 2 pods matching the template
  #is an optional field that specifies the number of old ReplicaSets to retain to allow rollback. Its ideal value depends on the frequency and stability of new Deployments
  revisionHistoryLimit: 10
  #is an optional field that specifies the minimum number of seconds for which a newly created Pod should be ready without any of its containers crashing
  minReadySeconds: 10
  strategy:
    type: RollingUpdate
    rollingUpdate:
      #  is an optional field that specifies the maximum number of Pods that can be created over the desired number of Pods
      maxSurge: 30%
      #is an optional field that specifies the maximum number of Pods that can be unavailable during the update process
      maxUnavailable: 10%
  template: # create pods using pod definition in this template
    metadata:
      # unlike pod-nginx.yaml, the name is not included in the meta data as a unique name is
      # generated from the deployment name 
      # 必须和Deployment metadata配置一致
      labels:
        dcos-service: app1-service3
        dcos-app: app1
    spec:
      affinity:
       podAntiAffinity:
         requiredDuringSchedulingIgnoredDuringExecution:
         - labelSelector:
             matchExpressions:
             - key: dcos-service 
               operator: In
               values:
               - app1-service3
           topologyKey: "kubernetes.io/hostname"
      containers:
      - name: nginx
        image: 172.18.2.103/dcos/nginx:1.1
        ports:
        - containerPort: 80
        # defines the health checking
        livenessProbe:
        # an http probe
          httpGet:
            path: /
            port: 80
          # length of time to wait for a pod to initialize
          # after pod startup, before applying health checking
          initialDelaySeconds: 15
          timeoutSeconds: 5
        resources:
          limits:
            cpu: 0.05
            memory: 30Mi
          requests:
            cpu: 0.05
            memory: 30Mi
```

