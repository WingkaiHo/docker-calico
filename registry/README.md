## 0 基本环境
   操作系统centos7, IP 地址是个192.168.20.10, 端口5000


## 1 制作SSL认证证书

### 1.1 openssl.cnf 配置文件修改

#### 1.1.1 内外单域名/单IP SSL认证证书
    在内网是使用IP， 如果有内部DNS通过域名访问。 以ip地址为访问方式, 配置文件`/etc/pki/tls/openssl.cnf`

```
//添加
[ v3_ca ]  
subjectAltName = IP:192.168.20.10   //是register所在机器的IP
```

#### 1.1.2 多IP和域名
    默认的 OpenSSL 生成的签名请求只适用于生成时填写的域名，即 `Common Name `填的是哪个域名，证书就只能应用于哪个域名，但是一般内网都是以 IP 方式部署，所以需要添加 SAN(Subject Alternative Name) 扩展信息，以支持多域名和IP

```
[ v3_req ]
# 修改 subjectAltName
subjectAltName = @alt_names 
[ alt_names ]
# 此节点[ alt_names ]为新增的，内容如下
IP.1=192.168.20.10   # 扩展IP(私服所在服务器IP)
DNS.1=*.xran.me     # 扩展域名(一般用于公网这里做测试)
DNS.2=*.baidu.com   # 可添加多个扩展域名和IP
```

### 1.2 创建CA证书和KEY文件
    创建仓库对应的证书和密钥:

```
register# mkdir -p certs
register# openssl req -newkey rsa:4096 -nodes -sha256 -keyout /root/certs/domain.key -x509 -days 365 -out /root/certs/domain.crt
Generating a 4096 bit RSA private key
..............++
..............++
writing new private key to 'certs/domain.key'
-----
You are about to be asked to enter information that will be incorporated
into your certificate request.
What you are about to enter is what is called a Distinguished Name or a DN.
There are quite a few fields but you can leave some blank
For some fields there will be a default value,
If you enter '.', the field will be left blank.
-----
Country Name (2 letter code) [XX]:CN
State or Province Name (full name) []:GuangDong
Locality Name (eg, city) [Default City]:GuangZhou
Organization Name (eg, company) [Default Company Ltd]:HongSuan
Organizational Unit Name (eg, section) []:IT
Common Name (eg, your name or your server's hostname) []:192.168.20.10:5000
Email Address []:xxx.yyy@ymail.com

```
提示输入时按照上面的填写，特别是192.168.20.10:5000这一行，其他随意。

### 1.3 创建Register 服务

    创建docker镜像仓库:
- Register 容器存储路径STORAGE_PATH=/registry-storage
- 仓库的镜像数据映射到本地目录`/var/lib/docker/registry/storage` 
- Register 映射本地端口5000
- 把仓库的容器`/certs` 映射本地`/root/certs`， 用于存放CA证书

```
 register# docker run --restart=always \
--name=registry  -e SETTINGS_FLAVOUR=dev \
-e STORAGE_PATH=/registry-storage \
-v /var/lib/docker/registry/storage:/registry-storage \
-u root -p 5000:5000 \
-v /root/certs:/certs \
-e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
-e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
registry:2
```

### 1.4 拷贝证书
 
   CA证书可以把他存放在docker目录下`/etc/docker/certs.d/192.168.20.10:5000/`， 也可以CA信息打印到文件`/etc/ssl/certs/ca-certificates.crt`，
操作步骤如下：
```
docker-client # mkdir -p /etc/docker/certs.d/192.168.20.10:5000/
docker-client # cp domain.crt /etc/docker/certs.d/192.168.20.10:5000/
docker-client # cat domain.crt | sudo tee -a /etc/ssl/certs/ca-certificates.crt
```

   每个需要访问仓库docker机器都需要拷贝CA证书。

`domain.crt`是刚才通过`openssl`生成的ca证书文件.

### 1.5 验证
  例如当前docker 机器有`grafana/grafana:2.6.0`,把他推送到新建仓库上

```
docker-client # docker tag grafana/grafana:2.6.0 192.168.20.10:5000/test/grafana:0.1
docker push 192.168.20.10:5000/test/grafana:0.1
The push refers to a repository [192.168.20.10:5000/test/grafana]
5f70bf18a086: Pushed
69f65076776d: Pushed
7cca4ac0616d: Pushed
c12ecfd4861d: Pushed
0.1: digest: sha256:e5c069a22542b0a28ba5c1f167b7068874d35eae6b5d5cc8d6b5164e22643ece size: 1978
```

可以看到成功，表明仓库配置正确


