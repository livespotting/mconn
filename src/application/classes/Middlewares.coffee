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

host = require("os").hostname()
Q = require("q")
zookeeper = require('node-zookeeper-client')

logger = require("./Logger")("Middlewares")
TaskData = require("./TaskData")
ZookeeperHandler = require("./ZookeeperHandler")

class Middlewares

  # get ZookeeperHandler when needed (delayed requirement)
  #
  # @return [ZookeeperHandler]
  #
  @ZookeeperHandler: ->
    return require("./ZookeeperHandler")

  @getModules: ->
    require("./Module").modules

  # middleware to append masterdata from zookeeper to request object
  #
  # @param [http.request] req
  # @param [http.response] res
  # @param [Function] next callback-method
  #
  @appendMasterDataToRequest: (req, res, next) ->
    logger.debug("INFO", "Fetching data from leading master")
    Middlewares.ZookeeperHandler().getMasterData()
    .then (masterdata) ->
      res.locals.mconnenv =
        masterdata: masterdata
        activatedModules: Middlewares.getModules()
        version: process.env.npm_package_version
      vars = require("../App").env_vars
      for e in vars
        res.locals.mconnenv[e.name] = process.env[e.name]
    .catch (error) ->
      logger.error(error, error.stack)
    .finally ->
      next()

  # middleware to add basic-auth support based on env-var MCONN_CREDENTIALS
  # @param [http.request] req
  # @param [http.response] res
  # @param [Function] next callback-method
  #
  @addBasicAuth: (req, res, next) =>
    cred_is_set = if process.env.MCONN_CREDENTIALS then true else false
    if cred_is_set is true then cred_not_valid = process.env.MCONN_CREDENTIALS.split(":").length isnt 2
    path_is_queue = (req.path is "/v1/queue" and req.method is "POST")
    path_is_ping = req.path is "/v1/ping"
    if cred_not_valid then logger.warn("\"MCONN_CREDENTIALS\" has an invalid formatting and basic-auth has been disabled!")
    if cred_is_set is false or cred_not_valid or path_is_queue or path_is_ping
      next()
    else
      @checkCredentials(req, res, next)

  @checkCredentials = (req, res, next) ->
    unauthorized = (res) ->
      res.set 'WWW-Authenticate', 'Basic realm=Authorization Required'
      res.sendStatus 401
    basicAuth = require("basic-auth")
    credentials = process.env.MCONN_CREDENTIALS.split(":")
    user = basicAuth(req)
    if !user or !user.name or !user.pass or credentials.length isnt 2
      logger.warn("Client \"" + req.ip + "\" tried to connect with wrong credentials!")
      return unauthorized(res)
    credentialsUser = process.env.MCONN_CREDENTIALS.split(":")[0]
    credentialsPass = process.env.MCONN_CREDENTIALS.split(":")[1]
    if user.name == credentialsUser and user.pass == credentialsPass
      next()
    else
      logger.warn("Client \"" + req.ip + "\" tried to connect with wrong credentials!")
      return unauthorized(res)

  @leaderIsOwnServer: (res) ->
    ip = process.env.MCONN_HOST
    port = process.env.MCONN_PORT
    protocol = "http://"
    ownServerurl = protocol + ip + ":" + port
    return ownServerurl is res.locals.mconnenv.masterdata.serverdata.serverurl

  @doProxyRequest: (req, res, next) ->
    logger.info("Proxying request to leader \"" + res.locals.mconnenv.masterdata.serverdata.serverurl + req.originalUrl + "\"")
    request = require("request")
    options =
      uri: res.locals.mconnenv.masterdata.serverdata.serverurl + req.originalUrl
      method: req.method
      json: req.body
    if process.env.MCONN_CREDENTIALS
      credentials = process.env.MCONN_CREDENTIALS.split(":")
      if credentials.length is 2
        credentialsUser = process.env.MCONN_CREDENTIALS.split(":")[0]
        credentialsPass = process.env.MCONN_CREDENTIALS.split(":")[1]
        options.auth =
          user: credentialsUser
          pass: credentialsPass
          sendImmediately: false
    request options, (err, response, body) ->
      if err
        logger.error("Error by proxying request to leader \"" + err.toString() + "\"", "")
      res.send(body)
      res.end()

  # middleware to route the request to master, if this server is not the master or to let it through if this is the master
  #
  # @param [http.request] req
  # @param [http.response] res
  # @param [Function] next callback-method
  #
  @route: (req, res, next) ->
    unless Middlewares.ZookeeperHandler().isMaster
      if Middlewares.leaderIsOwnServer(res)
        logger.warn "Leader data is the same as localhost, but could not verify this host to be leader. Waiting for the next leader-election"
        res.statusCode = 404
        res.end()
      else
        Middlewares.doProxyRequest(req, res, next)
    #this node is the master, so go to next middleware
    else
      next()

  # middleware to check if the request is a valid marathon request
  #
  # @param [http.request] req
  # @param [http.response] res
  # @param [Function] next callback-method
  #
  @checkRequestIsValid: (req, res, next) ->
    logger.debug("INFO", "Validate the incoming task")
    if req?.body?.eventType? and req.body.eventType is "status_update_event" or req.body.eventType is "scheduler_registered_event"
      next()
    else
      res.json(
        status: "error"
        message: "EventType has been rejected: " + req.body.eventType
      )
      logger.info("Ignoring eventType \"" + req.body.eventType + "\"")

  @expressLogger: (req, res, next) ->
    bytes = require('bytes')
    req._startTime = new Date
    log = ->
      code = res.statusCode
      len = parseInt(res.getHeader('Content-Length'), 10)
      if isNaN(len) then len = '' else len = ' - ' + bytes(len)
      duration = (new Date - req._startTime)
      url = (req.originalUrl || req.url)
      method = req.method
      if len isnt ''
        logger.info("#{method} \"#{url}\" #{code} #{duration}ms, #{req.ip}")
      else
        logger.info("#{method} \"#{url}\" #{code} #{duration}ms, #{req.ip}")
    res.on "finish", log
    res.on "close", log
    next()

  # middleware push the request as Task to QueueManagers
  #
  # @param [http.request] req
  # @param [http.response] res
  # @param [Function] next callback-method
  #
  @sendRequestToQueue: (req, res, next) ->
    logger.debug("INFO", "Processing task to \"QueueManager\"")
    #sync if leader changed on marathon
    if (req.body.eventType is "scheduler_registered_event")
      logger.info("Marathon has changed his leader! Sync all modules")
      modules = require("./Module").modules
      for modulename, module of modules
        do (module) ->
          logger.info("Syncing \"#{module.name}\"")
          module.doSync()
      res.end()
    # else it has to be the "status_update_event", so move on
    else
      QueueManager = require("./QueueManager")
      taskData = new TaskData(req)
      QueueManager.add(taskData)
      res.json(
        leader: res.locals.mconnenv.masterdata.serverdata.serverurl
        taskId: taskData.getData().taskId + "_" + taskData.getData().taskStatus
      )
      res.end()

module.exports = Middlewares
