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

Job = require("./Job")
logger = require("./Logger")("Middlewares")
ZookeeperHandler =  require("./ZookeeperHandler")

class Middlewares

  # get ZookeeperHandler when needed (delayed requirement)
  #
  # @return [ZookeeperHandler]
  #
  @ZookeeperHandler: ->
    return require("./ZookeeperHandler")

  # middleware to append masterdata from zookeeper to request object
  #
  # @param [http.request] req
  # @param [http.response] res
  # @param [Function] next callback-method
  #
  @appendMasterDataToRequest: (req, res, next) ->
    logger.debug("INFO", "Fetching data from leading master")
    Middlewares.ZookeeperHandler().getMasterData().then (masterdata) ->
      activatedModules = require("./Module").modules
      res.locals.mconnenv =
        masterdata: masterdata
        activatedModules: activatedModules
        version: process.env.npm_package_version
      vars = require("../App").env_vars
      for e in vars
        res.locals.mconnenv[e.name] = process.env[e.name]
      next()

  # middleware to append masterdetection to request object
  #
  # @param [http.request] req
  # @param [http.response] res
  # @param [Function] next callback-method
  #
  @appendIsMasterToRequest: (req, res, next) ->
    logger.debug("INFO", "Create proxy to leading master")
    if Middlewares.ZookeeperHandler().isMaster
      req.isMaster = true
    else
      req.isMaster = false
    next()

  # middleware to route the request to master, if this server is not the master or to let it through if this is the master
  #
  # @param [http.request] req
  # @param [http.response] res
  # @param [Function] next callback-method
  #
  @route: (req, res, next) ->
    unless Middlewares.ZookeeperHandler().isMaster
      logger.info( "Proxying request to leader " + res.locals.mconnenv.masterdata.serverdata.serverurl + req.originalUrl)
      request = require("request")
      options =
        uri: res.locals.mconnenv.masterdata.serverdata.serverurl + req.originalUrl
        method: req.method
        json: req.body
      request options, (err, response, body) ->
        if err
          logger.error("Error by proxying request to leader \"" + err.toString() + "\"")
        res.send(body)
        res.end()
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
    logger.debug("INFO", "Validate the incoming job")
    if req?.body?.eventType? and req.body.eventType is "status_update_event" or req.body.eventType is "scheduler_registered_event"
      next()
    else
      res.send(
        status: "warning",
        message: "ok, not 'status_udate_event'")
      res.end()
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
        logger.info("#{method} \"#{url}\" #{code} #{duration}ms")
      else
        logger.info("#{method} \"#{url}\" #{code} #{duration}ms")
    res.on "finish", log
    res.on "close", log
    next()

  # middleware push the request as Job to JobQueues
  #
  # @param [http.request] req
  # @param [http.response] res
  # @param [Function] next callback-method
  #
  @sendRequestToQueue: (req, res, next) ->
    logger.debug("INFO", "Processing job to \"JobQueue\"")

    #sync if leader changed on marathon
    if (req.body.eventType is "scheduler_registered_event")
      logger.info("LEADER CHANGE ON MARATHON: sync all modules!")
      modules = require("./Module").modules
      for modulename, module of modules
        do (module) ->
          logger.info("Syncing #{module.name}")
          module.doSync()
      res.end()
    # else it has to be hte "status_update_event", so move on
    else
      JobQueue = require("./JobQueue")
      mconnjob = new Job(req, res)
      JobQueue.add(mconnjob)
      res.send(
        status: "ok"
        message: "ok from " + res.locals.mconnenv.masterdata.serverdata.serverurl
        orderId: mconnjob.data.orderId
      )
      res.end()

module.exports = Middlewares
