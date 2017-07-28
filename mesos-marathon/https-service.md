{
  "id": "/https-nginx",
  "cmd": null,
  "cpus": 1,
  "mem": 128,
  "disk": 0,
  "instances": 1,
  "constraints": [
    [
      "hostname",
      "CLUSTER",
      "192.168.165.142"
    ]
  ],
  "container": {
    "type": "DOCKER",
    "volumes": [],
    "docker": {
      "image": "nginx:1.11.5",
      "network": "BRIDGE",
      "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 0,
          "servicePort": 10001,
          "protocol": "tcp",
          "name": "http",
          "labels": {}
        }
      ],
      "privileged": false,
      "parameters": [],
      "forcePullImage": false
    }
  },
  "healthChecks": [
    {
      "protocol": "TCP",
      "portIndex": 0,
      "gracePeriodSeconds": 300,
      "intervalSeconds": 60,
      "timeoutSeconds": 20,
      "maxConsecutiveFailures": 3,
      "ignoreHttp1xx": false
    }
  ],
  "labels": {
    // https 必须把此参都要加入，负责出现无法访问
    "HAPROXY_0_REDIRECT_TO_HTTPS": "true",
    "HAPROXY_0_STICKY": "true",
    "HAPROXY_GROUP": "external",
	// 自定义证书需要由用户制作好，通过nfs映射到容器里面
    "HAPROXY_0_SSL_CERT": "/user/ssl/certs/shsnc.pem",
    "HAPROXY_0_BACKEND_HTTP_OPTIONS": "  option forwardfor\n  no option http-keep-alive\n      http-request set-header X-Forwarded-Port %[dst_port]\n  http-request add-header X-Forwarded-Proto https if { ssl_fc }\n",
    "HAPROXY_0_VHOST": "shsnc.cn"
  },
  "portDefinitions": [
    {
      "port": 10001,
      "protocol": "tcp",
      "labels": {}
    }
  ]
}
