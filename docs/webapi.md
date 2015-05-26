# JSON/Web API

**Notice:**  
This is a pre-release! We can't guarantee that something you build today will work in the next release.

* [JobQueue](#jobqueue)
 * [GET /v1/jobqueue](#get-v1jobqueue)
 * [POST /v1/jobqueue](#post-v1jobqueue)
* [Modules](#modules)
 * [GET /v1/module/list](#get-v1modulelist)
 * [GET /v1/module/list/{moduleId}](#get-v1modulelistmoduleid)
 * [POST /v1/module/jobqueue/pause/{moduleId}](#post-v1modulejobqueuepausemoduleid)
 * [POST /v1/module/jobqueue/resume/{moduleId}](#post-v1modulejobqueueresumemoduleid)
 * [GET /v1/module/preset](#get-v1modulepreset)
 * [GET /v1/module/preset/{moduleId}](#get-v1modulepresetmoduleid)
 * [POST /v1/module/preset](#post-v1modulepreset)
 * [PUT /v1/module/preset](#put-v1modulepreset)
 * [DELETE /v1/module/preset](#delete-v1modulepreset)
* [System](#system)
 * [GET /v1/info](#get-v1info)
 * [GET /v1/leader](#get-v1leader)
 * [GET /v1/ping](#get-v1ping)
 * [GET /v1/exit/leader](#get-v1exitleader)
 * [GET /v1/exit/node](#get-v1exitnode)

## JobQueue

### GET /v1/jobqueue

Request:
```sh
GET /v1/jobqueue HTTP/1.1
Accept: */*
```

Response:
```json
[
    {
        "runtime": 0.8,
        "taskId": "bridged-webapp.715a2ddb-02f0-11e5-835c-a268d739d527",
        "appId": "/bridged-webapp",
        "marathonData": {
            "taskId": "bridged-webapp.715a2ddb-02f0-11e5-835c-a268d739d527",
            "taskStatus": "TASK_RUNNING",
            "appId": "/bridged-webapp",
            "host": "slave1.dev",
            "ports": [
                31006,
                31007
            ],
            "eventType": "status_update_event",
            "timestamp": "2015-05-25T15:12:23.338Z"
        },
        "state": "waiting for all modules to complete",
        "states": [
            {
                "modulename": "HelloWorld",
                "state": "started",
                "runtime": 0.8
            }
        ],
        "current": true
    }
]
```

### POST /v1/jobqueue

Request:
```sh
POST /v1/jobqueue HTTP/1.1
Accept: application/json
Content-Type: application/json; charset=utf-8

{
    "eventType": "status_update_event",
    "timestamp": "2015-05-25T15:12:24.140Z",
    "slaveId": "20150516-151938-1029963786-5050-2012-S1",
    "taskId": "bridged-webapp.7455ba9d-02f0-11e5-835c-a268d739d527",
    "taskStatus": "TASK_RUNNING",
    "appId": "/bridged-webapp",
    "host": "slave1.dev",
    "ports": [
        31004,31005
    ],
    "version": "2015-05-25T15:12:19.075Z"
}
```

Response:
```sh
ok
```

## Modules

### GET /v1/module/list

Request:
```sh
GET /v1/module/list HTTP/1.1
Accept: */*
```

Response:
```json
{
    "HelloWorld": {
        "name": "HelloWorld",
        "queue": {
            "tasks": [],
            "concurrency": 1,
            "saturated": null,
            "empty": null,
            "drain": null,
            "started": false,
            "paused": false
        },
        "logger": {
            "context": "MconnModule.HelloWorld"
        },
        "folder": "mconn-helloworld-master",
        "options": {},
        "timeout": 60000
    }
}
```

### GET /v1/module/list/{moduleId}

Request:
```sh
GET /v1/module/HelloWorld HTTP/1.1
Accept: */*
```

Response:
```json
{
    "HelloWorld": {
        "name": "HelloWorld",
        "queue": {
            "tasks": [],
            "concurrency": 1,
            "saturated": null,
            "empty": null,
            "drain": null,
            "started": false,
            "paused": false
        },
        "logger": {
            "context": "MconnModule.HelloWorld"
        },
        "folder": "mconn-helloworld-master",
        "options": {},
        "timeout": 60000
    }
}
```

### POST /v1/module/jobqueue/pause/{moduleId}

Request:
```sh
POST /v1/module/jobqueue/pause/HelloWorld HTTP/1.1
Accept: */*
```

Response:
```json
{
    "name": "HelloWorld",
    "queue": {
        "tasks": [],
        "concurrency": 1,
        "saturated": null,
        "empty": null,
        "drain": null,
        "started": true,
        "paused": true
    },
    "logger": {
        "context": "MconnModule.HelloWorld"
    },
    "folder": "HelloWorld",
    "options": {},
    "timeout": 60000,
    "currentJob": null
}
```

### POST /v1/module/jobqueue/resume/{moduleId}

Request:
```sh
POST /v1/module/jobqueue/resume/HelloWorld HTTP/1.1
Accept: */*
```

Response:
```json
{
    "name": "HelloWorld",
    "queue": {
        "tasks": [],
        "concurrency": 1,
        "saturated": null,
        "empty": null,
        "drain": null,
        "started": true,
        "paused": false
    },
    "logger": {
        "context": "MconnModule.HelloWorld"
    },
    "folder": "HelloWorld",
    "options": {},
    "timeout": 60000,
    "currentJob": null
}
```

### GET /v1/module/preset

Request:
```sh
GET /v1/module/preset HTTP/1.1
Accept: */*
```

Response:
```json
{
    "HelloWorld": [
        {
            "appId": "/bridged-webapp",
            "moduleName": "HelloWorld",
            "status": "enabled",
            "options": {
                "actions": {
                    "add": "Moin, Moin",
                    "remove": "Tschues"
                }
            },
            "lastEdit": false
        }
    ]
}
```

### GET /v1/module/preset/{moduleId}
Request:
```sh
GET /v1/module/preset/HelloWorld HTTP/1.1
Accept: */*
```

Response:
```json
[
    {
        "appId": "/bridged-webapp",
        "moduleName": "HelloWorld",
        "status": "enabled",
        "options": {
            "actions": {
                "add": "Moin, Moin",
                "remove": "Tschues"
            }
        },
        "lastEdit": false
    }
]
```

### POST /v1/module/preset

Request:
```sh
POST /v1/module/preset HTTP/1.1
Accept: application/json
Content-Type: application/json; charset=utf-8

{
    "appId": "/bridged-webapp",
    "moduleName": "HelloWorld",
    "status": "enabled",
    "options": {
        "actions": {
            "add": "Moin, Moin",
            "remove": "Tschues"
        }
    }
}
```

Response:
```sh
ok
```

### PUT /v1/module/preset

Request:
```sh
PUT /v1/module/preset HTTP/1.1
Accept: application/json
Content-Type: application/json; charset=utf-8

{
    "appId": "/bridged-webapp",
    "moduleName": "HelloWorld",
    "status": "enabled",
    "options": {
        "actions": {
            "add": "Hello, hello",
            "remove": "Bye"
        }
    }
}
```

Response:
```sh
ok
```

### DELETE /v1/module/preset

Request:
```sh
DELETE /v1/module/preset HTTP/1.1
Accept: application/json
Content-Type: application/json; charset=utf-8

{
    "appId": "/bridged-webapp",
    "moduleName": "HelloWorld"
}
```

Response:
```sh
ok
```

## System

### GET /v1/info

Request:
```sh
GET /v1/info HTTP/1.1
Accept: */*
```

Response:
```json
{
    "leader": "slave3.dev:31999",
    "env": {
        "MCONN_HOST": "slave1.dev",
        "MCONN_PORT": "31999",
        "MCONN_PATH": "/application",
        "MCONN_DEBUG": "false",
        "MCONN_JOBQUEUE_TIMEOUT": "60000",
        "MCONN_JOBQUEUE_SYNC_TIME": "600000",
        "MCONN_MODULE_PATH": "/mnt/mesos/sandbox",
        "MCONN_MODULE_START": "mconn-helloworld-master",
        "MCONN_MODULE_PREPARE": "true",
        "MCONN_ZK_HOSTS": "leader.mesos:2181",
        "MCONN_ZK_PATH": "/mconn",
        "MCONN_ZK_SESSION_TIMEOUT": "1000",
        "MCONN_ZK_SPIN_DELAY": "3000",
        "MCONN_ZK_RETRIES": "10",
        "MCONN_MARATHON_HOSTS": "leader.mesos:8080",
        "MCONN_MARATHON_SSL": "false"
    }
}
```

### GET /v1/leader

Request:
```sh
GET /v1/leader HTTP/1.1
Accept: */*
Accept-Encoding: gzip, deflate
```

Response:
```json
{
    "leader": "slave3.dev:31999"
}
```

### GET /v1/ping

Request:
```sh
GET /v1/ping HTTP/1.1
Accept: */*
```

Response:
```sh
pong
```

### GET /v1/exit/leader

Request:
```sh
GET /v1/exit/leader HTTP/1.1
Accept: */*
```

Response:
```sh
ok
```

### GET /v1/exit/node

Request:
```sh
GET /v1/exit/node HTTP/1.1
Accept: */*
```

Response:
```sh
ok
```
