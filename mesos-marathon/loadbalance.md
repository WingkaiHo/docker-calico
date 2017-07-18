1. 修改marathon-ld haproxy load balance 算法

```
{
  "id": "loadbalance1",
  "instances": 3,
  "labels": {
    "HAPROXY_GROUP":"external",
    "HAPROXY_0_VHOST":"mytask.acme.org",
    "HAPROXY_0_BALANCE":"leastconn" 
	
  },
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "nginx",
      "network": "USER",
      "portMappings": [{"containerPort": 80}]
    }
  },
  "ipAddress": {
      "networkName": "calico"
  }
}
```

2. 其他load balance 算法
roundrobin  Each server is used in turns, according to their weights.
              This is the smoothest and fairest algorithm when the server's
              processing time remains equally distributed. This algorithm
              is dynamic, which means that server weights may be adjusted
              on the fly for slow starts for instance. It is limited by
              design to 4095 active servers per backend. Note that in some
              large farms, when a server becomes up after having been down
              for a very short time, it may sometimes take a few hundreds
              requests for it to be re-integrated into the farm and start
              receiving traffic. This is normal, though very rare. It is
              indicated here in case you would have the chance to observe
              it, so that you don't worry.

  static-rr   Each server is used in turns, according to their weights.
              This algorithm is as similar to roundrobin except that it is
              static, which means that changing a server's weight on the
              fly will have no effect. On the other hand, it has no design
              limitation on the number of servers, and when a server goes
              up, it is always immediately reintroduced into the farm, once
              the full map is recomputed. It also uses slightly less CPU to
              run (around -1%).

  leastconn   The server with the lowest number of connections receives the
              connection. Round-robin is performed within groups of servers
              of the same load to ensure that all servers will be used. Use
              of this algorithm is recommended where very long sessions are
              expected, such as LDAP, SQL, TSE, etc... but is not very well
              suited for protocols using short sessions such as HTTP. This
              algorithm is dynamic, which means that server weights may be
              adjusted on the fly for slow starts for instance.

  first       The first server with available connection slots receives the
              connection. The servers are chosen from the lowest numeric
              identifier to the highest (see server parameter "id"), which
              defaults to the server's position in the farm. Once a server
              reaches its maxconn value, the next server is used. It does
              not make sense to use this algorithm without setting maxconn.
              The purpose of this algorithm is to always use the smallest
              number of servers so that extra servers can be powered off
              during non-intensive hours. This algorithm ignores the server
              weight, and brings more benefit to long session such as RDP
              or IMAP than HTTP, though it can be useful there too. In
              order to use this algorithm efficiently, it is recommended
              that a cloud controller regularly checks server usage to turn
              them off when unused, and regularly checks backend queue to
              turn new servers on when the queue inflates. Alternatively,
              using "http-check send-state" may inform servers on the load.

  source      The source IP address is hashed and divided by the total
              weight of the running servers to designate which server will
              receive the request. This ensures that the same client IP
              address will always reach the same server as long as no
              server goes down or up. If the hash result changes due to the
              number of running servers changing, many clients will be
              directed to a different server. This algorithm is generally
              used in TCP mode where no cookie may be inserted. It may also
              be used on the Internet to provide a best-effort stickiness
              to clients which refuse session cookies. This algorithm is
              static by default, which means that changing a server's
              weight on the fly will have no effect, but this can be
              changed using "hash-type".
