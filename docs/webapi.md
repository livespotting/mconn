# JSON/Web API

**Notice:**  
This is a pre-release! We can't guarantee that something you build today will work in the next release.

* [Queue](#queue)
 * [GET /v1/queue](#get-v1queue)
 * [POST /v1/queue](#post-v1queue)
* [Modules](#modules)
 * [GET /v1/module/inventory/{moduleId}](#get-v1moduleinventorymoduleid)
 * [GET /v1/module/list](#get-v1modulelist)
 * [GET /v1/module/list/{moduleId}](#get-v1modulelistmoduleid)
 * [GET /v1/module/queue/list/{moduleId}](#get-v1modulequeuelistmoduleid)
 * [POST /v1/module/queue/pause/{moduleId}](#post-v1modulequeuepausemoduleid)
 * [POST /v1/module/queue/resume/{moduleId}](#post-v1modulequeueresumemoduleid)
 * [GET /v1/module/preset](#get-v1modulepreset)
 * [GET /v1/module/preset/{moduleId}](#get-v1modulepresetmoduleid)
 * [POST /v1/module/preset](#post-v1modulepreset)
 * [PUT /v1/module/preset](#put-v1modulepreset)
 * [DELETE /v1/module/preset](#delete-v1modulepreset)
 * [POST /v1/module/sync](#post-v1modulesync)
 * [POST /v1/module/sync/{moduleId}](#post-v1modulesyncmoduleid)
* [System](#system)
 * [GET /v1/info](#get-v1info)
 * [GET /v1/leader](#get-v1leader)
 * [GET /v1/ping](#get-v1ping)
 * [POST /v1/exit/leader](#post-v1exitleader)
 * [POST /v1/exit/node](#post-v1exitnode)

## Queue

### GET /v1/queue

Request:
```sh
GET /v1/queue HTTP/1.1
Accept: */*
```

Response:
```json
[
    {
        "id": "bridged-webapp.715a2ddb-02f0-11e5-835c-a268d739d527_TASK_RUNNING",
        "data": {
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
        "moduleState": [
            {
                "name": "HelloWorld",
                "state": "started",
                "runtime": 0
            }
        ],
        "runtime": 0.8,
        "active": true
    }
]
```

### POST /v1/queue

Request:
```sh
POST /v1/queue HTTP/1.1
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

### GET /v1/module/inventory/{moduleId}

Request:
```sh
GET /v1/module/inventory/HelloWorld HTTP/1.1
Accept: */*
```

Response:
```json
[
    {
        "id": "bridged-webapp.28aa2a14-2157-11e5-9e08-56847afe9799",
        "data": {
            "customData": "Moin, Moin",
            "taskData": {
                "taskId": "bridged-webapp.28aa2a14-2157-11e5-9e08-56847afe9799",
                "taskStatus": "TASK_RUNNING",
                "appId": "/bridged-webapp",
                "host": "slave1.dev",
                "ports": [
                    31002,
                    31003
                ],
                "timestamp": 1435909578085
            }
        }
    }
]
```

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
            "tasks": [
                {
                    "data": {
                        "activeModules": [],
                        "taskId": "bridged-webapp.28aa2a14-2157-11e5-9e08-56847afe9799",
                        "taskStatus": "TASK_KILLED",
                        "appId": "/bridged-webapp",
                        "host": "slave1.dev",
                        "ports": [
                            31023
                        ],
                        "timestamp": 1435909542992,
                        "cleanup": true,
                        "state": "idle"
                    }
                }
            ],
            "concurrency": 1,
            "payload": 1,
            "started": true,
            "paused": false
        },
        "logger": {
            "context": "Module.HelloWorld"
        },
        "presets": [
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
        ],
        "folder": "HelloWorld",
        "options": {},
        "timeout": 60000,
        "syncInProgress": false,
        "activeTask": {
            "activeModules": [],
            "taskId": "bridged-webapp.67bb4g14-2157-11e5-9e08-56847afe9799",
            "taskStatus": "TASK_KILLED",
            "appId": "/bridged-webapp",
            "host": "slave1.dev",
            "ports": [
                31019
            ],
            "timestamp": 1435909558026,
            "cleanup": true,
            "state": "started",
            "start": 1435914049725
        }
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
    "name": "HelloWorld",
    "queue": {
        "tasks": [],
        "concurrency": 1,
        "payload": 1,
        "started": true,
        "paused": false
    },
    "logger": {
        "context": "Module.HelloWorld"
    },
    "presets": [
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
    ],
    "folder": "HelloWorld",
    "options": {},
    "timeout": 60000,
    "syncInProgress": false,
    "activeTask": {
        "activeModules": [],
        "taskId": "bridged-webapp.28aa2a14-2157-11e5-9e08-56847afe9799",
        "taskStatus": "TASK_RUNNING",
        "appId": "/bridged-webapp",
        "host": "slave1.dev",
        "ports": [
            31004
        ],
        "cleanup": true,
        "state": "finished",
        "start": 1435914144910,
        "timestamp": 1435914149916,
        "stop": 1435914149920
    }
}
```

### GET /v1/module/queue/list/{moduleId}

Request:
```sh
GET /v1/module/queue/list/HelloWorld HTTP/1.1
Accept: */*
```

Response:
```json
[
    {
        "id": "bridged-webapp.2a7414a6-2157-11e5-9e08-56847afe9799_TASK_KILLED",
        "data": {
            "taskId": "bridged-webapp.2a7414a6-2157-11e5-9e08-56847afe9799",
            "taskStatus": "TASK_KILLED",
            "appId": "/bridged-webapp",
            "host": "slave1.dev",
            "ports": [
                31614,
                31615
            ],
            "timestamp": 1435909588111
        },
        "cleanup": true,
        "moduleState": [],
        "runtime": 0.8,
        "state": "started"
    }
]
```

### POST /v1/module/queue/pause/{moduleId}

Request:
```sh
POST /v1/module/queue/pause/HelloWorld HTTP/1.1
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

### POST /v1/module/queue/resume/{moduleId}

Request:
```sh
POST /v1/module/queue/resume/HelloWorld HTTP/1.1
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

### POST /v1/module/sync

Request:
```sh
POST  /v1/module/sync HTTP/1.1
Accept: */*
```

Response:
```sh
ok
```

### POST /v1/module/sync/{moduleId}

Request:
```sh
POST  /v1/module/HelloWorld HTTP/1.1
Accept: */*
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
        "MCONN_LOGGER_LEVEL": "3",
        "MCONN_HOST": "slave1.dev",
        "MCONN_PORT": "31999",
        "MCONN_PATH": "/application",
        "MCONN_QUEUE_TIMEOUT": "60000",
        "MCONN_MODULE_PATH": "/mnt/mesos/sandbox",
        "MCONN_MODULE_PREPARE": "true",
        "MCONN_MODULE_START": "HelloWorld",
        "MCONN_MODULE_SYNC_TIME": "600000",
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

### POST /v1/exit/leader

Request:
```sh
POST /v1/exit/leader HTTP/1.1
Accept: */*
```

Response:
```sh
ok
```

### POST /v1/exit/node

Request:
```sh
POST /v1/exit/node HTTP/1.1
Accept: */*
```

Response:
```sh
ok
```
