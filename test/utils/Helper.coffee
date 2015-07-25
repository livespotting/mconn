#
# MConn Framework
# https://www.github.com/livespotting/mconn
#
# @copyright 2015 Livespotting Media GmbH
# @license Apache-2.0
#
# @author Christoph Johannsdotter [c.johannsdotter@livespottingmedia.com]
# @author Jan Stabenow [j.stabenow@livespottingmedia.com]
#

tcpp = require "tcp-ping"
Q = require "q"
request = require "request"

class Helper

  @webserverIsStarted: (port, server) ->
    deferred = Q.defer()
    intv = setInterval ->
      tcpp.probe '127.0.0.1', port, (err, available) ->
        if available
          #just to make sure, that all background processes of express are finished, wait 1 more second to resolve promise
          Q.delay(1000).then ->
            deferred.resolve()
            clearInterval(intv)
    , 200
    deferred.promise

  @webserverIsKilled: (port) ->
    deferred = Q.defer()
    intv = setInterval ->
      tcpp.probe '127.0.0.1', port, (err, available) ->
        if not available
          deferred.resolve()
          clearInterval(intv)
    deferred.promise

  @mockZookeeperHandler = ->
    mockZookeeperHandler = new Object()
    mockZookeeperHandler.nodes = new Array()
    mockZookeeperHandler.exists = (path) ->
      return Q.resolve(mockZookeeperHandler.nodes[path]?)
    mockZookeeperHandler.remove = (path) ->
      delete mockZookeeperHandler.nodes[path]
      return Q.resolve()
    mockZookeeperHandler.createNode = (path, data = new Buffer(""), acl, mode) ->
      mockZookeeperHandler.nodes[path] = new Buffer(data)
      return Q.resolve()
    mockZookeeperHandler.getData = (path) ->
      if mockZookeeperHandler.nodes[path]?
        if mockZookeeperHandler.nodes[path].toString()
          return Q.resolve JSON.parse(mockZookeeperHandler.nodes[path].toString())
        else
          return Q.resolve("")
      else
        return Q.reject("no data found in path " + path)
    mockZookeeperHandler.setData = (path, data, acl, mode) ->
      if mockZookeeperHandler.nodes[path]?
        mockZookeeperHandler.nodes[path] = new Buffer(JSON.stringify(data))
        return Q.resolve mockZookeeperHandler.nodes[path]
      else
        return Q.resolve(false)
    mockZookeeperHandler.createPathIfNotExist = (path) ->
      mockZookeeperHandler.createNode(path)
    mockZookeeperHandler.getMaster = ->
      #logger.debug("info", "ZookeeperHandler::getMaster()")
      deferred = Q.defer()
      deferred.resolve()
      mockZookeeperHandler.getData("master").then (data) ->
        deferred.resolve(data)
      .catch (error) ->
        deferred.reject(error)
      deferred.promise
    return mockZookeeperHandler

  @createMarathonInventoryItem = (taskId, appId = "/dev-app-1") ->
    item =
      'appId': appId
      'id': taskId
      'host': 'ac3.kiel'
      'ports': [
        31001
        31002
        31003
        31004
      ]
      'startedAt': '2014-08-28T12:16:28.930Z'
      'stagedAt': '2014-08-28T12:16:28.930Z'
      'version': '2014-08-28T12:16:28.930Z'
      'servicePorts': [ 10004 ]
      'healthCheckResults': [ {
        'taskId': 'dev-app-1.1431608371419-2ead-11e4-9fa7-f4ce46b2c61'
        'firstSuccess': '2014-08-28T12:16:28.930Z'
        'lastSuccess': '2014-08-28T12:16:28.930Z'
        'lastFailure': null
        'consecutiveFailures': 0
        'alive': true
      } ]
    item

  @createMarathonRequestdata = (port, appId, taskId = "A", status = "TASK_RUNNING", eventType = "status_update_event", host = "127.0.0.1") ->
    uri: "http://#{host}:#{port}/v1/queue"
    method: "POST"
    json:
      taskId: taskId
      taskStatus: status
      appId: appId
      host: host
      ports: [1234]
      eventType: eventType
      timestamp: new Date().getTime()

  @createPresetRequestdata = (port, appId, moduleName, status = "enabled", method = "POST", host = "127.0.0.1") ->
    uri: "http://#{host}:#{port}/v1/module/preset"
    method: method
    json:
      appId: appId
      moduleName: moduleName
      status: status
      options:
        actions:
          add: "Moin, Moin"
          remove: "Tschues"

module.exports = Helper
