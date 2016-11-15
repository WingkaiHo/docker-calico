## 0 基本环境
   操作系统centos7, IP 地址是个192.168.20.10, 端口5000


## 1 制作SSL认证证书

### 1.1 openssl.cnf 配置文件修改

#### 1.1.1 内外单域名/单IP SSL认证证书
    在内网是使用IP， 如果有内部DNS通过域名访问。 以ip地址为访问方式, 配置文件`/etc/pki/tls/openssl.cnf`
```
[ v3_ca ]  
subjectAltName = IP:192.168.20.10   //是register所在机器的IP
```

#### 1.1.2 多IP和域名
    默认的 OpenSSL 生成的签名请求只适用于生成时填写的域名，即 `Common Name `填的是哪个域名，证书就只能应用于哪个域名，但是一般内网都是以 IP 方式部署，所以需要添加 SAN(Subject Alternative Name) 扩展信息，以支持多域名和IP


```
registry# mkdir -p certs 

拷贝本目录下openssl.cnf 到你的certs目录
```
	
```
[req]
...
req_extensions = v3_req

[ v3_req ]
# Extensions to add to a certificate request
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
# 修改 subjectAltName
subjectAltName = @alt_names 

[ alt_names ]
DNS.1=hub.yourdomain1.com
DNS.2=hub.yourdomain2.com
DNS.3=hub.yourdomain3.com
```

### 1.2 创建CA证书和KEY文件
    创建仓库对应的证书和密钥:

```
registry# cd cert
registry# mkdir -p CA/{certs,crl,newcerts,private}
registry# touch CA/index.txt
registry# echo 00 > CA/serial

1.生成ca.key并自签署
registry# openssl req -new -x509 -days 3650 -keyout ca.key -out ca.crt -config openssl.cnf

2.生成server.key(名字不重要)
registry# openssl genrsa -out server.key 2048

3.生成证书签名请求
openssl req -new -key server.key -out server.csr -config openssl.cnf
Common Name 这个写主要域名就好了(注意：这个域名也要在openssl.cnf的DNS.x里)

4.查看请求文件
openssl req -text -noout -in server.csr 
应该可以看到这些内容：
    Certificate Request:
    Data:
    Version: 0 (0x0)
    Subject: C=US, ST=Texas, L=Fort Worth, O=My Company, OU=My Department,             CN=server.example
    Subject Public Key Info: Public Key Algorithm: rsaEncryption RSA Public Key: (2048 bit)
    Modulus (2048 bit): blahblahblah
    Exponent: 65537 (0x10001)
    Attributes:
    Requested Extensions: X509v3
    Basic Constraints: CA:FALSE
    X509v3 Key Usage: Digital Signature, Non Repudiation, Key Encipherment
    X509v3 Subject Alternative Name: DNS:hub.yourdomain1.com, DNS:hub.yourdomain2.com, DNS:hub.yourdomain3.com
    Signature Algorithm: sha1WithRSAEncryption

5.使用自签署的CA，签署server.scr
openssl ca -in server.csr -out server.crt -cert ca.crt -keyfile ca.key -extensions v3_req -config openssl.cnf
输入第一步设置的密码，一直按y就可以了


server.crt server.key就是registry服务器中使用的文件, ca.crt 就是给docker 用户使用的公钥。


### 1.3 创建Register 服务

    创建docker镜像仓库:
- Register 容器存储路径STORAGE_PATH=/registry-storage
- 仓库的镜像数据映射到本地目录`/var/lib/docker/registry/storage` 
- Register 映射本地端口5000
- 把仓库的容器`/certs` 映射本地`/root/certs`， 用于存放CA证书

```
registry# 
docker run --restart=always \
--name=registry  -e SETTINGS_FLAVOUR=dev \
-v /var/lib/docker/registry/storage:/var/lib/registry/docker/ \
-u root -p 5000:5000 \
-v /root/certs:/certs \
-e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
-e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
registry:2
```

### 1.4 拷贝证书
 
   CA证书发送各个docker client，把CA证书放到指定的地方，操作步骤如下:

centos docker 
```
docker-client # mkdir -p /etc/docker/certs.d/192.168.20.10:5000/
docker-client # cp domain.crt /etc/docker/certs.d/192.168.20.10:5000/
docker-client # cp domain.crt /etc/pki/ca-trust/source/anchors/192.168.20.10:5000.crt
docker-client # cp domain.crt  update-ca-trust
```

ubuntu docker 
```
docker-client # mkdir -p /etc/docker/certs.d/192.168.20.10:5000/
docker-client # cp domain.crt /etc/docker/certs.d/192.168.20.10:5000/
docker-client # cp domain.crt /usr/local/share/ca-certificates/192.168.20.10:5000.crt
docker-client # update-ca-certificates
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
