# decred-public-node-scripts
一键部署decred网络公共节点

### 备忘
#### 【！】脚本流程
1. 检测运行环境 检测服务器资源最低配置：1核1G10G可用空间,公网IP
2. 检测iptables之类是否已放通相关端口
3. 检测必要工具 wget、tar、gzip、systemd
3. 检测是否是首次安装：检测用户、端口、进程等标识

#### 安装模块
1. 创建普通用户decred:decred
2. 将数据文件放入$home文件下
3. 创建dcrd systemd服务文件基于decred项目组
4. 根据当前检测IP生成dcrd.conf文件
5. 启动dcrd节点

#### 卸载模块
1. 更新模块检测最新的release版本并更新二进制文件
2. 重启dcrd服务

#### 卸载模块
1. 停用服务
2. 删除dcrd.service配置文件
3. 删除dcrd二进制程序
4. 删除decred用户.dcrd配置文件

### 实验性
1. 加入自动检测文件权限相关的定期执行脚本
2. 加入定期自动更新最新dcrd版本 scriptname.sh update