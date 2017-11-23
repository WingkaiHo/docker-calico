### 生成 CA 自签证书
```
$ mkdir cert && cd cert
$ openssl genrsa -out ca-key.pem 2048
$ openssl req -x509 -new -nodes -key ca-key.pem -days 10000 -out ca.pem -subj "/CN=kube-ca"
```

### 编辑 openssl 配置
```
cp /etc/pki/tls/openssl.cnf .
vim openssl.cnf

// 主要修改如下
[req]
req_extensions = v3_req # 这行默认注释关着的 把注释删掉
// 下面配置是新增的
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = dashboard.mritd.me
DNS.2 = kibana.mritd.me
```

### 生成证书
```
$ openssl genrsa -out ingress-key.pem 2048
$ openssl req -new -key ingress-key.pem -out ingress.csr -subj "/CN=kube-ingress" -config openssl.cnf
$ openssl x509 -req -in ingress.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out ingress.pem -days 365 -extensions v3_req -extfile openssl.cnf
```
