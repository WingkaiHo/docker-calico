### 1. 容器探测条件
- `ExecAction`：在Container中执行指定的命令。如果命令退出状态码为0，则诊断被认为是成功的。

- `TCPSocketAction`：对指定端口上的Container的IP地址执行TCP检查。如果端口打开，则诊断被认为是成功的。

- `HTTPGetAction`：针对指定端口和路径上的容器的IP地址执行HTTP Get请求。如果响应的状态码大于等于200且小于400，则诊断被认为是成功的。

每个探头都有三个结果之一：

-成功：容器通过诊断。
-故障：容器故障诊断。
-未知：诊断失败，因此不应采取任何行动。

###2. 容器探针action

-`livenessProbe` : 指示容器是否正在运行。如果活动探测器失败，则kubelet会杀死Container，并且容器将受到其重新启动策略的影响。如果容器不提供活动探测器，则默认状态为Success.

- `readinessProbe`: 指示容器是否准备好service请求。如果准备探测失败，endpoints controller将从与Pod匹配的所有服务的endpoint中删除Pod的IP地址。在初始延迟之前的准备状态的默认状态为Failure。如果容器不提供readinessProbe，则默认状态为Success。


###3. 什么时候

- 如果容器中的过程能够在遇到问题或不健康的情况下自行崩溃，则不一定需要livenessProbe; kubelet将根据Pod的自动执行正确的操作restartPolicy。
- 如果您希望容器在探测失败时被杀死并重新启动，那么请指定一个livenessProbe，并指定一个restartPolicy=Always或OnFailure。
- 如果要仅在探测成功时才开始向Pod发送流量，请指定readinessProbe。在这种情况下，准备readinessProb可能与livenessProbe相同，但是规范中的readinessProbe存在意味着Pod将在没有接收到任何流量的情况下启动，并且只有在探测器开始成功后才开始接收流量。
- 如果您希望容器能够自己维护，您可以指定一个readinessProbe，该探测器检查特定于与livenessProbe不同的准备就绪的端点。
- 请注意，如果您只想在Pod被删除时能够排除请求，则不一定需要readinessProbe; 在删除时，Pod会自动将自身置于未完成状态，无论readinessProbe是否存在。当等待Pod中的容器停止时，Pod仍处于未完成状态。

