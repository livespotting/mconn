host = require("os").hostname()
logger = require("./MConnLogger")("MConnMiddlewares")
Q = require("q")
zookeeper = require('node-zookeeper-client')

MConnJob = require("./MConnJob")
MConnZookeeperHandler =  require("./MConnZookeeperHandler")

class MConnMiddlewares

  # get ZookeeperHandler when needed (delayed requirement)
  #
  # @return [MConnZookeeperHandler]
  #
  @MConnZookeeperHandler: ->
    return require("./MConnZookeeperHandler")

  # middleware to append masterdata from zookeeper to request object
  #
  # @param [http.request] req
  # @param [http.response] res
  # @param [Function] next callback-method
  #
  @appendMasterDataToRequest: (req, res, next) ->
    logger.debug("INFO", "Fetching data from leading master")
    MConnMiddlewares.MConnZookeeperHandler().getMasterData().then (masterdata) ->
      activatedModules = require("./MConnModule").modules

      req.mconnenv =
        masterdata: masterdata
        activatedModules: activatedModules
        version: process.env.npm_package_version
        hostname: process.env.HOSTNAME
        host: process.env.MCONN_HOST
        port: process.env.MCONN_PORT
        root_path: process.env.MCONN_PATH
        debug: process.env.MCONN_DEBUG
        jobqueue_timeout: process.env.MCONN_JOBQUEUE_TIMEOUT
        jobqueue_sync_time: process.env.MCONN_JOBQUEUE_SYNC_TIME
        module_path: process.env.MCONN_MODULE_PATH
        module_start: process.env.MCONN_MODULE_START
        module_prepare: process.env.MCONN_MODULE_PREPARE
        marathon_hosts: process.env.MCONN_MARATHON_HOSTS
        marathon_ssl: process.env.MCONN_MARATHON_SSL
        zk_hosts: process.env.MCONN_ZK_HOSTS
        zk_path: process.env.MCONN_ZK_PATH
        zk_session_timeout: process.env.MCONN_ZK_SESSION_TIMEOUT
        zk_spin_delay: process.env.MCONN_ZK_SPIN_DELAY
        zk_retries: process.env.MCONN_ZK_RETRIES
      next()

  # middleware to append masterdetection to request object
  #
  # @param [http.request] req
  # @param [http.response] res
  # @param [Function] next callback-method
  #
  @appendIsMasterToRequest: (req, res, next) ->
    logger.debug("INFO", "Create proxy to leading master")
    if MConnMiddlewares.MConnZookeeperHandler().isMaster
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
    logger.debug("INFO", "Proxying request to leader " + req.mconnenv.masterdata.serverdata.serverurl + "/v1/jobqueue")
    unless req.isMaster
      request = require("request")
      options =
        uri: req.mconnenv.masterdata.serverdata.serverurl + "/v1/jobqueue"
        method: "POST"
        json: req.body
      request options,(err, response, body) =>
        if err
          logger.logError("Error by proxying request to leader \"" + err.toString() + "\"")
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
    if req?.body?.eventType? and req.body.eventType is "status_update_event"
      next()
    else
      res.send(
        status: "warning",
        message: "ok, not 'status_udate_event'")
      res.end()
      logger.logInfo("Ignoring eventType \"" + req.body.eventType + "\"")

  # middleware push the request as MConnJob to JobQueues
  #
  # @param [http.request] req
  # @param [http.response] res
  # @param [Function] next callback-method
  #
  @sendRequestToQueue: (req, res, next) ->
    logger.debug("INFO", "Processing job to \"MConnJobQueue\"")
    MConnJobQueue = require("./MConnJobQueue")
    mconnjob = new MConnJob(req, res)
    MConnJobQueue.add(mconnjob)
    res.send(
      status: "ok"
      message: "ok from " + req.mconnenv.masterdata.serverdata.serverurl
      orderId: mconnjob.data.orderId
    )
    res.end()

module.exports = MConnMiddlewares
