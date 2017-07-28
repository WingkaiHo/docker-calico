下面是一个WordPress示例，同样web-app依赖mysql-db才能正常运行。

内部服务使用mesos-dns，外部服务使用lb
{
    "id": "wordpress",
    "apps": [
        {
            "id": "web-app",
            "instances": 1,     //实例数目
            "cpus": 0.1,		//cpu限制
            "mem": 128.0,		//内存限制		
            "container": {
                "type": "DOCKER",
                "docker": {
                    "image": "wordpress",
                    "network": "USER",
                    "parameters": [
						// 环境变量
                        { "key": "env", "value": "WORDPRESS_DB_PASSWORD=My-Pw-123" },
						// 内部dns <服务id>.<appid>.<域名称>.shsnc  域名称: 测试域/生产/
                        { "key": "env", "value": "WORDPRESS_DB_HOST=mysql-db.wordpress.marathon.shsnc:3306" }                     
                    ],
					// 对外映射端口
                    "portMappings": [
                        {
                            "containerPort": 80,
                            "hostPort": 0,
                            "servicePort": 0,
                            "protocol": "tcp"
                        }
                    ]
                }
            },
			// 添加器群约束
			"constraints": [
				[
					"hostname",
					"UNIQUE"
				],
				[
					"rack",
					"CLUSTER",
					"1"
				]
			],
            "ipAddress": {
				// 使用calico 网络 
                "networkName": "calico"
            },
            "labels": {
				// 申请外部域名
                "HAPROXY_GROUP":"external", 
				// 外部域名的名称 0/1.. 对应portMappings对外映射端口端口号码，可以多个
                "HAPROXY_0_VHOST":"wordpress.shsnc.com"
				// marathon-lb haproxy 上负载均衡算法: 
                // 1. roundrobin(轮询)默认选项，
				// 2. leastconn 最少连接，source
				// 3. source: 源ip 
				// 0/1.. 对应portMappings对外映射端口端口号码 
				"HAPROXY_0_BALANCE":"leastconn"
				// 更多HAPROXY label可以参考下面网址
				// 例如 
						"HAPROXY_0_REDIRECT_TO_HTTPS":"true"
				//      "HAPROXY_0_SSL_CERT“: ”/etc/ssl/certs/nginx.mesosphere.com"
				//		"HAPROXY_0_USE_HSTS" : true
				// https://libraries.io/github/mesosphere/marathon-lb
            },
			// 健康检查
            "healthChecks": [
                {
				  // 检查的协议 HTTP， TCP， UDP 
                  "protocol": "HTTP",
				  // 路径 HTTP 才支持路径
                  "path": "/",
                  "portIndex": 0,
                  "gracePeriodSeconds": 300,
				  // 检查的间隔
                  "intervalSeconds": 60,
				  // 超时时间
                  "timeoutSeconds": 20,
				  // 连续多少次失败以后认为是不健康
                  "maxConsecutiveFailures": 3
                }
            ],
            "dependencies": [
				// 依赖： 启动这个服务前，下面的服务必须是检查通过以后再启动
                "/wordpress/mysql-db"
            ]                   
        },
        {
            "id": "mysql-db",
            "instances": 1,
            "cpus": 0.1,
            "mem": 512.0,
            "disk": 0.0,
            "container": {
                "type": "DOCKER",
                "docker": {
                    "image": "mysql",
                    "network": "USER",
					// 环境变量
                    "parameters": [
                        { "key": "env", "value": "MYSQL_ROOT_PASSWORD=My-Pw-123" }                   
                    ],
					// 这个内部数据库没有通过marathon-lb导出，服务就通过内部dns获取ip地址
					//  <服务id>.<appid>.<域名称>.shsnc  域名称: 测试域/生产/
                    "portMappings": [
                        {
                            "containerPort": 3306,
                            "hostPort": 0,
                            "protocol": "tcp"
                        }
                    ]
                }
            },	
			// 添加器群约束
			"constraints": [
				[
					"hostname",
					"UNIQUE"
				],
				[
					"rack",
					"CLUSTER",
					"1"
				]
			],
            "ipAddress": {
                "networkName": "calico"
            },
            "healthChecks": [
                {
                    "protocol": "TCP",
                    "portIndex": 0,
                    "maxConsecutiveFailures": 3
                }
            ]
        }
    ]
}

