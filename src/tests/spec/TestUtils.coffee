Docker = require('dockerode');
fs = require "fs"
isBoot2Docker = ->
  return process.env.DOCKER_CERT_PATH?

if isBoot2Docker()
  docker = new Docker({
    protocol: 'https',
    host: '192.168.99.100',
    port: process.env.DOCKER_PORT || 2375,
    ca: fs.readFileSync(process.env.DOCKER_CERT_PATH + '/ca.pem'),
    cert: fs.readFileSync(process.env.DOCKER_CERT_PATH + '/cert.pem'),
    key: fs.readFileSync(process.env.DOCKER_CERT_PATH + '/key.pem')
  });
else
  docker = new Docker({socketPath:"/var/run/docker.sock"})

zookeeper = require('node-zookeeper-client')
Q = require("q")
os = require("os")
startZookeeperContainer = (testingHost = process.env.MCONN_TESTING_HOST, testingPort = process.env.MCONN_TESTING_PORT)->
  deferred = Q.defer()
  docker.createContainer {Image: "jplock/zookeeper", name: "ZOOKEEPER_TEST"}, (err, zookeepercontainer) ->
    if err then throw err
    zookeepercontainer.start {"PortBindings": {"2181/tcp": [{"HostPort": testingPort, "HostIp":testingHost}]}}, (err, data)->
      if err then throw err
      deferred.resolve(zookeepercontainer)
  return deferred.promise


startApplicationContainer = (hostport) ->
  deferred = Q.defer()
  sys = require('sys')
  exec = require('child_process').exec
  exec "ip route | awk '/docker/ { print $NF }'", (error, stdout, stderror) ->
    hostip = if process.env.MCONN_HOSTIP then process.env.MCONN_HOSTIP else stdout.split("\n")[0]
    docker.createContainer
      Volumes: if process.env.LOCAL then ["/application"] else []
      Env: [
        "MODE=" + if process.env.MODE then process.env.MODE else "test"
        "MCONN_HOST=" + hostip
        "DEBUG=true"
        "MCONN_PORT=" + hostport
        "AX_SESSION_TIMEOUT=180000"
      ]
      Image: "lsm_mconn"
      name: "lsm_mconn_" + hostport
    , (err, mconncontainer) ->
      if err then throw err
      mconncontainer.start
        Binds: if process.env.LOCAL then [process.env.LOCAL + ":/application"] else []
        PortBindings:
          "1234/tcp": [
            HostPort: hostport
            HostIp: hostip
          ]
        Links:["ZOOKEEPER:ZOOKEEPER"]
      , (err, stream)->
        mconncontainer.inspect (err, data) =>
          deferred.resolve(
            container: mconncontainer
            inspection: data
          )
  return deferred.promise

removeContainer = (containerId)->
  deferred = Q.defer()
  sys = require('sys')
  exec = require('child_process').exec

  command1 = "docker kill #{containerId}"
  command2 = "docker rm  #{containerId}"
  unless isBoot2Docker()
    command1 = "sudo #{command1}"
    command2 = "sudo #{command2}"
  exec command1, (error, stderror, stdout) ->
    if error then throw error
    exec command2, (error, stderror, stdout) ->
      if error then throw error
      deferred.resolve()
  deferred.promise


removeAllContainers = (containers) ->
  deferred = Q.defer()
  sys = require('sys')
  exec = require('child_process').exec

  command1 = "docker kill ZOOKEEPER_TEST"
  command2 = "docker rm ZOOKEEPER_TEST"
  unless isBoot2Docker()
    command1 = "sudo #{command1}"
    command2 = "sudo #{command2}"
  exec command1, (error, stderror, stdout) ->
    exec command2, (error, stderror, stdout) ->
      deferred.resolve()
  deferred.promise

samplePostData = (serverurl)->
  o = new Object()
  o =
    taskId: "dev-app-1.217b833a-2ead-11e4-9fa7-f4ce46b2c61"
    taskStatus: "TASK_RUNNING"
    appId: "/dev-app-1"
    host: "ac3.kiel"
    ports: [31001,31002,31003,31004]
    eventType: "status_update_event"
    timestamp: "2014-08-28T12:16:28.930Z"
connectToZookeeper = ->
  deferred = Q.defer()
  client =  zookeeper.createClient(process.env.MCONN_ZK_HOSTS,null)
  client.connect()
  setTimeout ->
    if client.state?.name? and client.state.name is "DISCONNECTED"
      console.log "COULD NOT CONNECT TO ZOOKEEPER!!!"
  , 10000
  client.on "connected", ->
    deferred.resolve(client)
  deferred.promise



deleteFolderRecursive = (path) ->
  fs = require('fs')
  if fs.existsSync(path)
    fs.readdirSync(path).forEach (file, index) ->
      curPath = path + '/' + file
      if fs.lstatSync(curPath).isDirectory()
        # recurse
        deleteFolderRecursive curPath
      else
        # delete file
        fs.unlinkSync curPath
      return
    fs.rmdirSync path
  return

createFakeZookeeperHandler = ->
  #create fake zookeeperhandler object
  fakeZookeeperHandler = new Object()
  fakeZookeeperHandler.nodes = new Array()
  fakeZookeeperHandler.exists = (path) ->
    return Q.resolve(fakeZookeeperHandler.nodes[path]?)

  fakeZookeeperHandler.remove = (path) ->
    delete fakeZookeeperHandler.nodes[path]
    return Q.resolve()


  fakeZookeeperHandler.createNode = (path, data = new Buffer(""), acl, mode) ->

    fakeZookeeperHandler.nodes[path] = new Buffer(data)
    return Q.resolve()

  fakeZookeeperHandler.getData = (path) ->
    if fakeZookeeperHandler.nodes[path]?
      if fakeZookeeperHandler.nodes[path].toString()
        return Q.resolve JSON.parse(fakeZookeeperHandler.nodes[path].toString())
      else
        return Q.resolve("")
    else
      return Q.reject("no data found in path " + path)

  fakeZookeeperHandler.setData = (path, data, acl, mode) ->
    if fakeZookeeperHandler.nodes[path]?
      fakeZookeeperHandler.nodes[path] = new Buffer(JSON.stringify(data))
      return Q.resolve fakeZookeeperHandler.nodes[path]
    else
      return Q.resolve(false)

  fakeZookeeperHandler.getMaster =  ->
        #logger.debug("info", "ZookeeperHandler::getMaster()")
    deferred = Q.defer()
    deferred.resolve()
    fakeZookeeperHandler.getData("master").then (data) ->
      deferred.resolve(data)
    .catch (error) ->
      deferred.reject(error)
    deferred.promise
  return fakeZookeeperHandler




killEnvironment = ->
  deferred = Q.defer()
  sys = require('sys')
  exec = require('child_process').exec

  command1 = "docker kill lsm_mconn_1234 lsm_mconn_1235 lsm_mconn_1236 lsm_mconn_1237 ZOOKEEPER"
  command2 = "docker rm lsm_mconn_1234 lsm_mconn_1235 lsm_mconn_1236 lsm_mconn_1237 ZOOKEEPER"
  unless isBoot2Docker()
    command1 = "sudo #{command1}"
    command2 = "sudo #{command2}"
  exec command1, (error, stderror, stdout) ->
    exec command2, (error, stderror, stdout) ->
      console.log "\nstopped TestEnvironment".green
      Q.delay(5000).then ->
        deferred.resolve()
  deferred.promise



module.exports.docker = docker
module.exports.startZookeeperContainer = startZookeeperContainer
module.exports.startApplicationContainer = startApplicationContainer
module.exports.removeContainer = removeContainer
module.exports.removeAllContainers = removeAllContainers
module.exports.connectToZookeeper = connectToZookeeper
module.exports.samplePostData = samplePostData
module.exports.createFakeZookeeperHandler = createFakeZookeeperHandler
module.exports.killEnvironment = killEnvironment
module.exports.deleteFolderRecursive = deleteFolderRecursive
