## Enviroments

- [MCONN_LOGGER_LEVEL](#mconn_logger_level)
- [MCONN_HOST](#mconn_host)
- [MCONN_PORT](#mconn_port)
- [MCONN_PATH](#mconn_path)
- [MCONN_CREDENTIALS](#mconn_credentials)
- [MCONN_MODULE_PATH](#mconn_module_path)
- [MCONN_MODULE_START](#mconn_module_start)
- [MCONN_MODULE_PREPARE](#mconn_module_prepare)
- [MCONN_ZK_HOSTS](#mconn_zk_hosts)
- [MCONN_ZK_PATH](#mconn_zk_path)
- [MCONN_ZK_TIMEOUT](#mconn_zk_session_timeout)
- [MCONN_ZK_SPIN](#mconn_zk_spin_delay)
- [MCONN_ZK_RETRIES](#mconn_zk_retries)
- [MCONN_MARATHON_HOSTS](#mconn_marathon_hosts)
- [MCONN_MARATHON_SSL](#mconn_marathon_ssl)

#### MCONN_LOGGER_LEVEL
Set the logging level of the application. The values are "1" for error, "2" for error and warnings, "3" for error, warnings and info or "4" for error, warnings, info and debug.

Default-Value:
`` 3 ``

#### MCONN_HOST
The hostname of the MConn-Node.

Default-Value:
```coffee
if process.env.HOST then process.env.HOST else "127.0.0.1"
```

#### MCONN_PORT
The port of the webserver

Default-Value:
```coffee
if process.env.PORT0 then process.env.PORT0 else "1234"
```

#### MCONN_PATH
MConn needs to know its absolute path to build the module structure.

Default-Value (look at the Dockerfile) is
```sh
"/mconn"
```

#### MCONN_CREDENTIALS
By setting this value to a valid format you enable the basic authentication of the HTTP-Server. The correct formatting is ``user:password ``. Don't use a colon (:) for username or password.

Default-Value:
``not set ``

#### MCONN_QUEUE_TIMEOUT
This is the max. lifetime in milliseconds before the QueueManager switches a taskState to "error".

Default-Value:
`` 60000 ``

#### MCONN_MODULE_PATH
This is  the path where MConn Modules, defined by MCONN_MODULE_START environment, can be found.

Example: 
- MCONN_MODULE_START=HelloWorld
- MCONN_MODULE_PATH=/mnt/mesos/sandbox

MConn will search in "/mnt/mesos/sandbox" for a folder named "HelloWorld".

Default-Value:
```coffee
if process.env.MESOS_SANDBOX then process.env.MESOS_SANDBOX else "/mconn/modules"
```

#### MCONN_MODULE_PREPARE
This function compiles the coffee-files of the selected modules before installing the npm-dependencies. If you want to inclue a module in native javascript you need to set this value to `` false ``

Default-Value:
`` true ``

#### MCONN_MODULE_START
When starting the process, MCONN searches the folder name you have chosen.

Default-Value:
``not set ``

#### MCONN_MODULE_SYNC_TIME
Global time in milliseconds to start the Marathon-Sync

Default-Value:
`` 600000 ``

#### MCONN_ZK_HOSTS
The Zookeeper-Hosts. Possible is `` leader.mesos:2181 `` or `` 10.10.10.10:2181,10.10.10.11:2181,... ``

Default-Value:
```coffee
if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" 
else "leader.mesos:2181"
```

#### MCONN_ZK_PATH
This value is the name of the path that MConn will create and use on Zookeeper-Store 

Default-Value:
```coffee
if process.env.MARATHON_APP_ID then process.env.MARATHON_APP_ID else "/mconn"
```

#### MCONN_ZK_SESSION_TIMEOUT
Session timeout in milliseconds.

Default-Value:
`` 1000 ``

#### MCONN_ZK_SPIN_DELAY
The delay (in milliseconds) between each connection attempts.

Default-Value:
`` 3000 ``

#### MCONN_ZK_RETRIES
The number of retry attempts for connection loss exception.

Default-Value:
`` 10 ``

#### MCONN_MARATHON_HOSTS
The addresses of the Marathon-Hosts. Possible is `` leader.mesos:8080 `` or `` admin:password@10.10.10.10:8080,admin:password@10.10.10.11:8080,... ``

Default-Value:
`` leader.mesos:8080 ``

#### MCONN_MARATHON_SSL
Set this env to `` true ``, if your Marathon instances are using HTTPS (self sight certificates are allowed)

Default-Value:
`` false ``
