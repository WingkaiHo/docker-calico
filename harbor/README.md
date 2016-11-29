## 简介
   Harbor是VMware公司最近开源的企业级Docker Registry项目, 项目地址为https://github.com/vmware/harbor 其目标是帮助用户迅速搭建一个企业级的Docker registry服务。它以Docker公司开源的registry为基础，提供了管理UI, 基于角色的访问控制(Role Based Access Control)，AD/LDAP集成、以及审计日志(Audit logging) 等企业用户需求的功能，同时还原生支持中文。Harbor的每个组件都是以Docker容器的形式构建的，使用Docker Compose来对它进行部署。用于部署Harbor的Docker Compose模板位于 /Deployer/docker-compose.yml，由5个容器组成：

- Proxy: 由Nginx 服务器构成的反向代理。
- Registry:由Docker官方的开源registry 镜像构成的容器实例。
- UI: 即架构中的core services, 构成此容器的代码是Harbor项目的主体。
- Mysql: 由官方MySql镜像构成的数据库容器。
- Log: 运行着rsyslogd的容器，通过log-driver的形式收集其他容器的日志。
       这几个容器通过Docker link的形式连接在一起，在容器之间通过容器名字互相访问。对终端用户而言，只需要暴露proxy （即Nginx）的服务端口。

## 安装和配置Harbor
   克隆源码:
```
git clone https://github.com/vmware/harbor
```

### 1.1 安装docker-compose

   通过pip安装docker-compose

```
harbor# yum install python-pip.noarch
harbor# pip install docker-compose
harbor# pip install --upgrade  backports.ssl-match-hostname
``` 

### 1.2 配置harbor 本地验证以及http协议

  修改`harbor.cfg`

  配置样例如下:
```
配置样例如下 :

## Configuration file of Harbor

#The IP address or hostname to access admin UI and registry service.
#DO NOT use localhost or 127.0.0.1, because Harbor needs to be accessed by external clients.
# 指定 hostname，一般为IP，或者域名，用于登录 Web UI 界面
hostname = 192.168.20.10

#The protocol for accessing the UI and token/notification service, by default it is http.
#It can be set to https if ssl is enabled on nginx.
# URL 访问方式，SSL 需要配置 nginx
ui_url_protocol = http

#Email account settings for sending out password resetting emails.
# 邮件相关信息配置，如忘记密码发送邮件
email_server = smtp.xxxxxx.com
email_server_port = 465
email_username = reg@mritd.me
email_password = xxxxxx
email_from = docker <reg@mritd.me>
email_ssl = true

##The password of Harbor admin, change this before any production use.
#默认的 Harbor 的管理员密码，管理员用户名默认 admin,用于web页面，以及仓库登录
harbor_admin_password = Harbor12345

##By default the auth mode is db_auth, i.e. the credentials are stored in a local database.
#Set it to ldap_auth if you want to verify a user's credentials against an LDAP server.
# 指定 Harbor 的权限验证方式，Harbor 支持本地的 mysql 数据存储密码，同时也支持 LDAP
auth_mode = db_auth

#The url for an ldap endpoint.
# 如果采用了 LDAP，此处填写 LDAP 地址
ldap_url = ldaps://ldap.mydomain.com

#The basedn template to look up a user in LDAP and verify the user's password.
# LADP 验证密码的方式(我特么没用过这么高级的玩意)
ldap_basedn = uid=%s,ou=people,dc=mydomain,dc=com

#The password for the root user of mysql db, change this before any production use.
# mysql 数据库 root 账户密码
db_password = root123

#Turn on or off the self-registration feature
# 是否允许开放注册
self_registration = on

#Turn on or off the customize your certicate
# 允许自签名证书
customize_crt = on

#fill in your certicate message
# 自签名证书信息
crt_country = CN
crt_state = State
crt_location = CN
crt_organization = mritd
crt_organizationalunit = mritd
crt_commonname = mritd.me
crt_email = reg.mritd.me
```

 修改域名相关的配置

```
grep "reg.mydomain.com" -RnI *
Deploy/config/jobservice/env:13:EXT_ENDPOINT=http://reg.mydomain.com
Deploy/config/registry/config.yml:24:    realm: http://reg.mydomain.com/service/token
Deploy/config/ui/env:8:HARBOR_REG_URL=reg.mydomain.com
Deploy/config/ui/env:10:HARBOR_URL=http://reg.mydomain.com
Deploy/config/ui/env:19:EXT_ENDPOINT=http://reg.mydomain.com
docs/prepare-swagger.sh:3:SERVER_IP=reg.mydomain.com
tests/hostcfg.sh:4:sudo sed "s/reg.mydomain.com/$IP/" -i Deploy/harbor.cfg

deploy 目录下的都需要修改, 把域名修改到你所需要域名/或者ip
```

### 1.3 部署harbor

    运行./prepare脚本更新配置。完成配置后，就可以使用docker-compose快速部署harbor

```
 harbor# cd $HARBOR_HOME/Deploy/
 harbor# ./prepare
 harbor# docker-compose up -d
```

    安装完成后，访问Web UI，地址：http://bind_addr，即配置的hostname地址，端口为80

### 1.4 配置docker client

    docker client 通过registry上传下载镜像时候需要登录验证。 系统默认情况下提供Admin用户,里面预先创建`library`仓库目录，
我们可以通过admin测docker client是否能够上传/下载镜像。

#### 1.4.1 配置docker 服务
    以上是UI界面的使用，接下来介绍如何使用docker client进行镜像的管理，由于harbor只支持Registry V2 API，因此Docker client版本必须`>= 1.6.0`。
由于我们配置认证服务使用的是http，Docker认为是不安全的，要使用我们部署的镜像仓库，需要配置本地docker，修改配置文件`/etc/systemd/system/docker.service.d/override.conf`为：
```
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --insecure-registry 192.168.20.10 --registry-mirror=192.168.20.10
```

 -参数:`--insecure-registry 192.168.20.10`代表我们通信使用http通信.
 -参数:`--registry-mirror=192.168.20.10` 把仓库作为缓冲，如果在仓库192.168.20.10不存在镜像再去官方仓库去取镜像。

   修改以后需要重新加载服务配置

```
 docker-client# systemctl daemon-reload
 docker-client# systemctl restart docker 
```

#### 1.4.2 验证能否登录

   docker 需要验证登录仓库以后才可以提交下载镜像:
```
 docker-client# docker login -u admin -p Harbor12345 192.168.20.10 
 Login Succeeded
```
  Admin帐号在默认情况下有library目录可以使用，例如向仓库上传本地镜像`ubuntu:14.04`

- 然后为该镜像打上新的标签，标签格式为：Harbor地址/项目名/镜像名称:镜像标签
```
 docker-client# docker tag ubuntu:14.04  192.168.20.10/library/ubuntu:14.04
 docker-client# docker push ubuntu:14.04 192.168.20.10/library/ubuntu:14.04
```


### 1.5 harbor 配置为https模式

#### 1.5.1 修改`harbor.cfg`配置

  配置样例如下:
```

## Configuration file of Harbor

#The IP address or hostname to access admin UI and registry service.
#DO NOT use localhost or 127.0.0.1, because Harbor needs to be accessed by external clients.
# 指定 hostname，一般为IP，或者域名，用于登录 Web UI 界面
hostname = 192.168.20.10

#The protocol for accessing the UI and token/notification service, by default it is http.
#It can be set to https if ssl is enabled on nginx.
# URL 访问方式，SSL 需要配置 nginx
ui_url_protocol = https

#Email account settings for sending out password resetting emails.
# 邮件相关信息配置，如忘记密码发送邮件
email_server = smtp.xxxxxx.com
email_server_port = 465
email_username = reg@mritd.me
email_password = xxxxxx
email_from = docker <reg@mritd.me>
email_ssl = true

##The password of Harbor admin, change this before any production use.
#默认的 Harbor 的管理员密码，管理员用户名默认 admin,用于web页面，以及仓库登录
harbor_admin_password = Harbor12345

##By default the auth mode is db_auth, i.e. the credentials are stored in a local database.
#Set it to ldap_auth if you want to verify a user's credentials against an LDAP server.
# 指定 Harbor 的权限验证方式，Harbor 支持本地的 mysql 数据存储密码，同时也支持 LDAP
auth_mode = db_auth

#The url for an ldap endpoint.
# 如果采用了 LDAP，此处填写 LDAP 地址
ldap_url = ldaps://ldap.mydomain.com

#The basedn template to look up a user in LDAP and verify the user's password.
# LADP 验证密码的方式(我特么没用过这么高级的玩意)
ldap_basedn = uid=%s,ou=people,dc=mydomain,dc=com

#The password for the root user of mysql db, change this before any production use.
# mysql 数据库 root 账户密码
db_password = root123

#Turn on or off the self-registration feature
# 是否允许开放注册
self_registration = on

#Turn on or off the customize your certicate
# 允许自签名证书
customize_crt = on

#fill in your certicate message
# 自签名证书信息
crt_country = CN
crt_state = State
crt_location = CN
crt_organization = mritd
crt_organizationalunit = mritd
crt_commonname = mritd.me
crt_email = reg.mritd.me
```

 修改域名相关的配置

```
grep "reg.mydomain.com" -RnI *
Deploy/config/jobservice/env:13:EXT_ENDPOINT=http://reg.mydomain.com
Deploy/config/registry/config.yml:24:    realm: http://reg.mydomain.com/service/token
Deploy/config/ui/env:8:HARBOR_REG_URL=reg.mydomain.com
Deploy/config/ui/env:10:HARBOR_URL=http://reg.mydomain.com
Deploy/config/ui/env:19:EXT_ENDPOINT=http://reg.mydomain.com
docs/prepare-swagger.sh:3:SERVER_IP=reg.mydomain.com
tests/hostcfg.sh:4:sudo sed "s/reg.mydomain.com/$IP/" -i Deploy/harbor.cfg

deploy 目录下的都需要修改, 把域名修改到你所需要域名/或者ip
```

#### 1.5.2 配置SSL认证证书

##### 1.5.2.1 内外单域名/单IP SSL认证证书
    在内网是使用IP， 如果有内部DNS通过域名访问。 以ip地址为访问方式, 配置文件`/etc/pki/tls/openssl.cnf`
```
[ v3_ca ]  
subjectAltName = IP:192.168.20.10   //是register所在机器的IP
```

##### 1.5.2.2 多IP和域名
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
#### 1.5.3 创建仓库对应的证书和密钥:

```
registry# mkdir -p certs
registry# openssl req -newkey rsa:4096 -nodes -sha256 -keyout /root/certs/harbordomain.key -x509 -days 365 -out /root/certs/harbordomain.crt
Generating a 4096 bit RSA private key
..............++
..............++
writing new private key to certs/domain.key
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
Common Name (eg, your name or your server's hostname) []:192.168.20.10
Email Address []:xxx.yyy@ymail.com

```
提示输入时按照上面的填写，特别是192.168.20.10这一行，其他随意。如有内部有dns可以配置配置为站点.

#### 1.5.4 配置nigix https模式

    默认的`nigix.conf`文件是没有ssl配置，需要把`nginx.https.conf`替换`nigix.conf`, 修改

```
server_name 192.168.20.9;

# SSL
ssl_certificate /etc/nginx/cert/harbordomain.crt;
ssl_certificate_key /etc/nginx/cert/harbordomain.key;
```

按照配置把ca文件和密钥拷贝到目录`$harbor_home/Deploy/config/nginx/cert/`，文件命名必须和配置文件一致.

配置完毕以后按照1.3 部署方法就可以部署。


#### 1.5.5 docker client 配置证书
   CA证书发送各个docker client，把CA证书放到指定的地方，操作步骤如下:
centos docker 
```
docker-client # mkdir -p /etc/docker/certs.d/192.168.20.10:5000/
docker-client # cp domain.crt /etc/docker/certs.d/192.168.20.10:5000/
docker-client # cp domain.crt /etc/pki/ca-trust/source/anchors/192.168.20.10:5000.crt
docker-client # update-ca-trust
```

ubuntu docker 
```
docker-client # mkdir -p /etc/docker/certs.d/192.168.20.10:5000/
docker-client # cp domain.crt /etc/docker/certs.d/192.168.20.10:5000/
docker-client # cp domain.crt /usr/local/share/ca-certificates/192.168.20.10:5000.crt
docker-client # update-ca-certificates
```
   每个需要访问仓库docker机器都需要拷贝CA证书。

- [配置VMWare harbor仓库异地备份](configure_https_registry_replication.md)
