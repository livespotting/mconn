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
