### 1 Kubernetes 服务暴露介绍
   从 kubernetes 1.2 版本开始，kubernetes提供了 Ingress 对象来实现对外暴露服务；到目前为止 kubernetes 总共有三种暴露服务的方式:
   - LoadBlancer Service
   - NodePort Service
   - Ingress

### 1.1、LoadBlancer Service
    LoadBlancer Service 是 kubernetes 深度结合云平台的一个组件；当使用 LoadBlancer Service 暴露服务时，实际上是通过向底层云平台申请创建一个负载均衡器来向外暴露服务；目前 LoadBlancer Service 支持的云平台已经相对完善，比如国外的 GCE、DigitalOcean，国内的 阿里云，私有云 Openstack 等等，由于 LoadBlancer Service 深度结合了云平台，所以只能在一些云平台上来使用

### 1.2、NodePort Service
     NodePort Service 顾名思义，实质上就是通过在集群的每个 node 上暴露一个端口，然后将这个端口映射到某个具体的 service 来实现的，虽然每个 node 的端口有很多(0~65535)，但是由于安全性和易用性(服务多了就乱了，还有端口冲突问题)实际使用可能并不多

### 1.3、Ingress
   Ingress 这个东西是 1.2 后才出现的，通过 Ingress 用户可以实现使用 nginx 等开源的反向代理负载均衡器实现对外暴露服务，以下详细说一下 Ingress，毕竟 traefik 用的就是 Ingress
   使用 Ingress 时一般会有三个组件:

   - 反向代理负载均衡器
   - Ingress Controller
   - Ingress

### 1.3.1、反向代理负载均衡器

    反向代理负载均衡器很简单，说白了就是 nginx、apache 什么的；在集群中反向代理负载均衡器可以自由部署，可以使用 Replication Controller、Deployment、DaemonSet 等等，不过个人喜欢以 DaemonSet 的方式部署，感觉比较方便

### 1.3.2、Ingress Controller
    Ingress Controller 实质上可以理解为是个监视器，Ingress Controller 通过不断地跟 kubernetes API 打交道，实时的感知后端 service、pod 等变化，比如新增和减少 pod，service 增加与减少等；当得到这些变化信息后，Ingress Controller 再结合下文的 Ingress 生成配置，然后更新反向代理负载均衡器，并刷新其配置，达到服务发现的作用

### 1.3.3、Ingress

   Ingress 简单理解就是个规则定义；比如说某个域名对应某个 service，即当某个域名的请求进来时转发给某个 service;这个规则将与 Ingress Controller 结合，然后 Ingress Controller 将其动态写入到负载均衡器配置中，从而实现整体的服务发现和负载均衡


## 2 配置ingress 服务

```
$ git clone https://github.com/kubernetes/ingress.git
```

### 2.1 配置默认的后端
   我们知道 前端的 Nginx 最终要负载到后端 service 上，那么如果访问不存在的域名咋整？官方给出的建议是部署一个 默认后端，对于未知请求全部负载到这个默认后端上；这个后端啥也不干，就是返回 404，部署如下:
```
$cd ingress/examples/deployment/nginx/ 
$kubectl create -f default-backend.yaml
 deployment "default-http-backend" created
 service "default-http-backend" created
```

### 2.2 部署 Ingress Controller
    部署完了后端就得把最重要的组件 Nginx+Ingres Controller(官方统一称为 Ingress Controller) 部署上. 
    官方的 Ingress Controller 有个坑，至少我看了 DaemonSet 方式部署的有这个问题：没有绑定到宿主机 80 端口，也就是说前端 Nginx 没有监听宿主机 80 端口

```
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: nginx-ingress-controller
  labels:
    k8s-app: nginx-ingress-controller
  namespace: kube-system
spec:
  replicas: 1
  template:
    metadata:
      labels:
        k8s-app: nginx-ingress-controller
      annotations:
        prometheus.io/port: '10254'
        prometheus.io/scrape: 'true'
    spec:
      # hostNetwork makes it possible to use ipv6 and to preserve the source IP correctly regardless of docker configuration
      # however, it is not a hard dependency of the nginx-ingress-controller itself and it may cause issues if port 10254 already is taken on the host
      # that said, since hostPort is broken on CNI (https://github.com/kubernetes/kubernetes/issues/31307) we have to use hostNetwork where CNI is used
      # like with kubeadm
      # enable hostNetwork
      hostNetwork: true
      terminationGracePeriodSeconds: 60
      containers:
      - image: gcr.io/google_containers/nginx-ingress-controller:0.9.0-beta.5
        name: nginx-ingress-controller
        readinessProbe:
          httpGet:
            path: /healthz
            port: 10254
            scheme: HTTP
        livenessProbe:
          httpGet:
            path: /healthz
            port: 10254
...
```

   修改完后就创建nginx-ingress-controller
```
$kubectl create -f nginx-ingress-controller.yaml
```

   编辑ingress入口文件

```
$vim dashboard-graphite-ingress.yml

apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: dashboard-kibana-ingress
  namespace: kube-system
spec:
  rules:
  - host: dashboard.test
    http:
      paths:
      - backend:
          serviceName: kubernetes-dashboard
          servicePort: 80
  - host: graphite.test
    http:
      paths:
      - backend:
          serviceName: graphite
          servicePort: 80
```

  应用ingress入口文件
```
$kubectl apply -f dashboard-graphite-ingress.yml
```

  这两个域名是不存在的需要在`/etc/hosts`配置,  例如kubernetes ip地址是192.168.10.1

```
192.168.10.1 dashboard.test
192.168.10.1 graphite.test
```

  配置以后就可以通过浏览器访问下面两个网址

http://dashboard.test
http://graphite.test
