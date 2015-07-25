### Changes from 0.0.9 to 0.0.10

- implemented MCONN_MODULE_PREPARE function
 - now we use "npm install --production" 
 - "false" needs compiled (or native code) js-files and installed npm-packages
- implemented the correct MCONN_MARATHON_HOSTS function
 - now MCONN supports an array of Marathon-Hosts like "admin:password@10.10.10.10:8080,admin:password@10.10.10.11:8080,..."
- MCONN_MARATHON_SSL function is now implemented
 - supports HTTPS with a self signed certificate for the sync-function
- MCONN_QUEUE_TIMEOUT is now usable (will kill each task if the timeout has been reached)
- added Basic-Auth-Support (user:password)
 - can be set by env MCONN_CREDENTIALS=user:password
 - Leader-Proxy will use this too, if activated
 - "/v1/ping" and "/v1/queue" is unprotected! because the [Marathon-HTTPCallback](https://mesosphere.github.io/marathon/docs/event-bus.html) currently doesn't support Basic-Auth (we try to implement the [Marathon-Event-Stream](https://mesosphere.github.io/marathon/docs/rest-api.html#event-stream) in the future)
- refactored the TaskStatus-Handling
 - Module-Class now checks the defined TaskStatus-Handlings of the installed Modules
 - TaskStatus now can be an "undefiniedStatus" and will close a task without error and an action
- refactored the QueueManager-Class
 - TaskStates are no longer be saved on ZK-Store because MConn starts a Marathon-Sync by Leader-Election (reduced the complexity)
- reintegrate custom Module-CSS (have a look at the HelloWorld-Example)
- cleanup NODE-Structure
- cleanup for "/v1/module/list/HelloWorld"
- cleanup index-class
- spent more time on the webapi responses
 - refactored http-messages and status codes
 - POST /v1/module/sync + /{moduleid} responds after it knows if marathon is reachable
 - POST/PUT/DELETE /v1/module/preset + /{moduleid} responds after the leader has sent the "ok"
- refactored the function that checks if the leader is localhost
- added more integration-tests
- added more unit-tests
- updated npm dependencies
- updated bower packages
- switched to node:0.12.7-slim (~620mb vs. ~830mb)
- added new module structure


### Changes from 0.0.8 to 0.0.9

- new env MCONN_LOGGER_LEVEL
 - 1 = Errors
 - 2 = Errors, Warning
 - 3 = Errors, Warning, Info (default)
 - 4 = Errors, Warning, Info, Debug 
- removed time based sync on non-leader
- cleanup the Zk-Node
- PUT /v1/module/preset will now be forwared to the leader
- presets can be disabled now
- the queue show now the task age
- better error reporting (log level 4 now shows error-stacks)
- reduced zookeeper-communication
 - leaderdata will be cached
 - presets will be cached
- modules queue and inventory are now accessable over the WebAPI
- module queue will be tested now
- module inventory will be tested now
- module sync will be tested now
- updated npm dependencies
- updated bower packages
- updated to node v. 0.12.5


### Changes from 0.0.7 to 0.0.8

* re-engineered naming and code cleaned up:
 * Job (Class) -> TaskData (Class)
 * JobQueue (Class) -> QueueManager (Class)
 * JobQueue -> Queue
   * /v1/jobqueue -> /v1/queue
 * currentJob -> activeTask
 * etc.
* implemented mocha and chai (first testings):
 * LeaderElection (5 tests) 
 * Middlewares (9 tests)
 * Module (13 tests)
 * TaskData (8 tests)
 * WebAPI (33 tests)

*Notice: 
Please cleanup your ZK-Node like*
```sh
zkCli.sh rmr /mconn
```
*and update you Marathon-HTTPCallback to "../v1/queue" like*
```sh
curl -X DELETE leader.mesos:8080/v2/eventSubscriptions?callbackUrl=http://mconn.marathon.mesos:31999/v1/jobqueue
curl -X POST leader.mesos:8080/v2/eventSubscriptions?callbackUrl=http://mconn.marathon.mesos:31999/v1/queue
```

### Changes from 0.0.6 to 0.0.7

* switched env MCONN_DEBUG to NODE_ENV
 * modes are "production" (default) or "development"
* inventory-sync now react on Marathon-Event "scheduler_registered_event" (Marathon LeaderElection)
* inventory-sync is now executable through the WebAPI (POST /v1/module/sync or + /{modulename})
* fixed NODE_EXISTS[-110] on startup if the path exists
* moved Express-Logger to Middlewares
* POST/PUT/DELETE /v1/module/preset now proxying to leader
* POST /v1/module/jobqueue/pause/:modulename now proxying to leader
* POST /v1/module/jobqueue/resume/:modulename now proxying to leader
* reduced the complexity of inventory-sync
* ui components now installed by bower
* switched serverside-routing to client-routing with angular routes
* presets are getting updated now through websockets
* added watch-mode to grunt building-process (executed by 'grunt watch' or 'grunt')

*Notice:*
*In the next release (0.0.8) we will re-engineer the naming e.g. job->task. Please don't use the current code for productions!*

### Changes from 0.0.5 to 0.0.6

* update to Node 0.12.4
* update NPM dependencies
* update frontend libs (angular, bootstrap, ..)
* first code cleanup
  * you have to clean up the mconn-node on zookeeper!!!
* switch Ant to Grunt
  * move static webserver files (templates, libs, css) to folder static/
  * minify frontend jscript for productive (default) usage
  * minify cssfiles
  * use jscript maps for productive (default) usages
  * add leverage browser-caching for all assets 
  * remove bin folder from repo (bin folder is now being created by executing ‚grunt build‘)
* render jade-templates
  * reduces pageload from ~600ms up to ~8ms
* POST to exit leader or node
