Utils = require "./../spec/TestUtils"
require("colors")
Q = require("q")
request = require("request")
startZookeeperContainer = Utils.startZookeeperContainer
startApplicationContainer = Utils.startApplicationContainer
removeContainer = Utils.removeContainer
removeAllContainers = Utils.removeAllContainers
connectToZookeeper= Utils.connectToZookeeper

isBoot2Docker = ->
  return process.env.DOCKER_CERT_PATH?

program = require("commander")
program
.version('1.0')
.option("--kill", "kill app")
.option("--start", "start app")
.option("--updatePreset", "updatePreset")
.option('--appId [value]', 'appId')
.option('--host [value]', 'host')
.option('--taskToken [value]', 'taskToken to create a reusable taskid')
.option('--taskStatus [value]', 'taskStatus TASK_RUNNING or TASK_KILLED')
.option('--presetOptionsAdd [value]', 'options for add')
.option('--presetOptionsRemove [value]', 'options for remove')
.option('--eventType [value]', 'eventtype of marathonEventbus')
.option('--moduleName [value]', 'moduleName for Preset')
.option('--mconnServer [value]', "define the server to send the call to")
.parse(process.argv);

program.on("--help", ->
  console.log "ADD PRESET: coffee src/tests/livetest/Livetest.coffee --updatePreset --mconnServer 192.168.99.100:1235 --appId dev-app-1 --moduleName HelloWorld --presetOptionsAdd MoinMoin --presetOptionsRemove Tschuess"
)


createMarathonRequest = (appId = program.appId, host = program.host, status = program.taskStatus, ports=[11,22,33], customTaskToken = program.taskToken, eventType = program.eventType)->
  deferred = Q.defer()
  options =
    uri: "http://" + program.mconnServer + "/v1/jobqueue"
    method: "POST"
    json: createAppData(appId, host, status, ports, customTaskToken, eventType)
  console.log(options)
  request options,(err, response, body) ->
    if err then console.log err.red else console.log JSON.stringify(body, null, 2).blue
    deferred.resolve()
  deferred.promise

createAppData = (appId, host, status, ports, customTaskToken, eventType)->
  o = new Object()
  o =
  taskId: "#{appId}." + customTaskToken
  taskStatus: status
  appId: "/" + appId
  host: host
  ports: ports
  eventType: if eventType then eventType else "status_update_event"
  timestamp: new Date().getTime()


updatePreset =  (appId, moduleName, add, remove) =>
  options =
    uri: "http://" + if program.mconnServer then program.mconnServer + "/v1/module/preset"
    method: "POST"
    json:
      appId: "/" + appId
      moduleName: moduleName
      options:
        actions:
          add: add
          remove: remove
  request options,(err, response, body) ->
    if err then console.log err.red else console.log JSON.stringify(body, null, 2).blue

if program.kill then createMarathonRequest(program.appId, program.host, "TASK_KILLED")
if program.start then createMarathonRequest(program.appId, program.host, "TASK_RUNNING")

if program.updatePreset
  updatePreset(appId = program.appId, moduleName = program.moduleName, add = program.presetOptionsAdd, remove = program.presetOptionsRemove)


simulateMarathon= ->
  # DEV APP 1
  #scale up
  setInterval ->
    createMarathonRequest("dev-app-1", "host1.local","TASK_RUNNING",[101,102,103,104])
    createMarathonRequest("dev-app-1", "host2.local","TASK_RUNNING",[101,102,103,104])
    createMarathonRequest("dev-app-1", "host3.local","TASK_RUNNING",[101,102,103,104])
  , 10000
  #scale down
  setInterval ->
    createMarathonRequest("dev-app-1", "host1.local","TASK_KILLED",[101,102,103,104])
    createMarathonRequest("dev-app-1", "host2.local","TASK_KILLED",[101,102,103,104])
    createMarathonRequest("dev-app-1", "host3.local","TASK_KILLED",[101,102,103,104])
  , 30000

  # DEV APP 2
  #scale up
  setInterval ->
    createMarathonRequest("dev-app-2", "host1.local","TASK_RUNNING",[201,202,203,204])
    createMarathonRequest("dev-app-2", "host2.local","TASK_RUNNING",[201,202,203,204])
  , 20000
  #scale down
  setInterval ->
    createMarathonRequest("dev-app-2", "host1.local","TASK_KILLED",[201,202,203,204])
    createMarathonRequest("dev-app-2", "host2.local","TASK_KILLED",[201,202,203,204])
  , 30000

  # DEV APP 2
  #scale up
  setInterval ->
    createMarathonRequest("dev-app-3", "host3.local","TASK_RUNNING",[301,302,303])
  , 5000
  #scale down
  setInterval ->
    createMarathonRequest("dev-app-3", "host3.local","TASK_KILLED",[301,302,303])
  , 40000
