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

express = require("express")
Q = require("q")
require("colors")

logger = require("./classes/Logger")("App")
Middlewares = require("./classes/Middlewares")
Module = require("./classes/Module")

# Holds all relevant data like app globals, webserver and init-processes
#
class App
  # environment variables for the application
  @env_vars: [
    name: "MCONN_HOST"
    required: false
    default: if process.env.HOST then process.env.HOST else "127.0.0.1"
    description: "Hostname or IP of this server"
  ,
    name: "MCONN_PORT"
    required: false
    default: if process.env.PORT0 then process.env.PORT0 else "1234"
    description: "Webserver Port of this server"
  ,
    name: "MCONN_PATH"
    required: false
    default: if process.env.JENKINS_HOME then "/jenkins/workspace/mconn/" else "/application"
    description: "Path of the modules to be loaded"
  ,
    name: "MCONN_DEBUG"
    required: false
    default: false
    description: "Generate more messages on stdout"
  ,
    name: "MCONN_JOBQUEUE_TIMEOUT"
    required: false
    default: 60000
    description: "Timout until a job has to be finished"
  ,
    name: "MCONN_JOBQUEUE_SYNC_TIME"
    required: false
    default: 600000
    description: "Global time to start Marathon-Sync"
  ,
    name: "MCONN_MODULE_PATH"
    required: false
    default: if process.env.MESOS_SANDBOX then process.env.MESOS_SANDBOX else "/application/modules"
    description: "Path of the modules to be loaded"
  ,
    name: "MCONN_MODULE_START"
    required: false
    default: ""
    description: "List of activated modules"
  ,
    name: "MCONN_MODULE_PREPARE"
    required: false
    default: "true"
    description: "run npm install in the modules folder before start it"
  ,
    name: "MCONN_ZK_HOSTS"
    required: false
    default: if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" else "leader.mesos:2181"
    description: "Zookeeper instances"
  ,
    name: "MCONN_ZK_PATH"
    required: false
    default: if process.env.MARATHON_APP_ID then process.env.MARATHON_APP_ID else "/mconn"
    description: "Zookeeper node path"
  ,
    name: "MCONN_ZK_SESSION_TIMEOUT"
    required: false
    default: "1000"
    description: "Zookeeper session timeout"
  ,
    name: "MCONN_ZK_SPIN_DELAY"
    required: false
    default: "3000"
    description: "Zookeeper spin delay"
  ,
    name: "MCONN_ZK_RETRIES"
    required: false
    default: "10"
    description: "Zookeeper max connection retries"
  ,
    name: "MCONN_MARATHON_HOSTS"
    required: false
    default: "leader.mesos:8080"
    description: "Marathon Host (currently only one is supported)"
  ,
    name: "MCONN_MARATHON_SSL"
    required: false
    default: "false"
    description: "Marathon-URL is HTTPS (currently not included)"
  ]

  # delayed requirement of ZookeeperHandler
  #
  @ZookeeperHandler: ->
    require("./classes/ZookeeperHandler")

  # check environment and set defaults, if env-vars are not set
  #
  @checkEnvironment: ->
    logger.debug("INFO", "Check enviroments")
    return Q.fcall =>
      killProcess = false
      for e in @env_vars
        if process.env[e.name]?
          logger.info("ENV \"#{e.name}=" + process.env[e.name] + "\", #{e.description}")
        else if e.required
          console.log ("No value set for env #{e.name}, but it is required!").red.bold
          killProcess = true
        else
          process.env[e.name] = e.default
          logger.info("ENV \"#{e.name}=#{e.default}\", default value, #{e.description}")
      if killProcess
        console.log ("MConn stops because required env-vars are not set").red.bold
        process.kill()
      return

  # connect to zookeeper and register events
  #
  @initZookeeper: ->
    logger.debug("INFO", "Initiate ZookeeperHandler")
    ZookeeperHandler = require("./classes/ZookeeperHandler")
    ZookeeperHandler.registerEvents()
    ZookeeperHandler.connect()

  # router to hold all routes defined by modules
  @moduleRouter: express.Router()

  # webserver
  @app: express()

  # holder for all static routes of modules to load css/js of modules, too
  @expressStatics: {}

  # load all modules
  @initModules: ->
    logger.debug("INFO", "Initiate Module")
    return Module.loadModules(@moduleRouter, @expressStatics)

  @renderApplication: ->
    logger.info("Rendering main layout")
    deferred = Q.defer()
    jade = require("jade")
    Middlewares = require("./classes/Middlewares")
    Middlewares.ZookeeperHandler().getMasterData()
    .then (masterdata) =>
      activatedModules = require("./classes/Module").modules
      mconnenv =
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
      html = jade.renderFile(__dirname + '/webserver/views/jobqueue.jade',
        modulename: "home"
        mconnenv: mconnenv
      )
      @app.set("cachedLayout", html)
      logger.info("rendering main layout done")
      deferred.resolve()
    .catch (error) ->
      logger.error("Error rendering main layout: " + error)
      deferred.resolve()
    deferred.promise
  @registerWebsocketEvents: (io) ->
    modules = require("./classes/Module").modules
    for modulename, module of modules
      io.of("/#{modulename}").on("connection", (socket) ->
        require("./classes/JobQueue").WS_SendAllJobs(socket)
      )
    io.of("/home").on("connection", (socket) ->
      require("./classes/JobQueue").WS_SendAllJobs(socket)
    )

  # start the webserver
  #
  # @param [Number] port of webserver to listen to
  #
  @startWebserver: (port = process.env.MCONN_PORT) ->
    try
      logger.debug("INFO", "Initiate webserver")
      path = require("path")
      cookieParser = require("cookie-parser")
      bodyParser = require("body-parser")
      config = require("./webserver/config/config")
      compression = require("compression")
      oneYear = 31536000
      @app.locals.jsfiles = config.getJavascriptFiles()
      @app.locals.cssfiles = config.getCssFiles()
      routes = require("./webserver/routes/index")


      # view engine setup
      @app.set "views", path.join(__dirname, "webserver/views")
      @app.set 'json spaces', 4
      @app.set "view engine", "jade"
      @app.locals.basedir = path.join(__dirname, "webserver/views")

      # MConn Express Logger
      @app.use (req, res, next) ->
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

      @app.use bodyParser.json()
      @app.use bodyParser.urlencoded({extended: true})
      @app.use cookieParser()
      @app.use compression()
      # add middlewares
      @app.use Middlewares.appendMasterDataToRequest
      @app.use "/v1/jobqueue", Middlewares.appendIsMasterToRequest
      @app.post "/v1/jobqueue", Middlewares.checkRequestIsValid
      @app.post "/v1/jobqueue", Middlewares.route
      @app.post "/v1/jobqueue", Middlewares.sendRequestToQueue
      for modulename, staticPath of @expressStatics
        @app.use "/#{modulename}/", express.static(staticPath, {maxage: oneYear})
      @app.use express.static(path.join(__dirname, "webserver/public"), {maxage: oneYear})
      @app.use "/", @moduleRouter
      @app.use "/", routes

      #/ catch 404 and forwarding to error handler
      @app.use (req, res, next) ->
        err = new Error("Not Found")
        err.status = 404
        next err

      # production error handler
      # no stacktraces leaked to user
      @app.use (err, req, res, next) ->
        res.status err.status or 500
        logger.error(err + ": " + req.url)
        res.send("{\"message\":\"URI not found: " + req.url + "\"}")
        res.end()

      http = require('http')

      server = http.createServer(@app).listen(port)
      io = require('socket.io').listen(server)
      @app.set("io", io)
      @registerWebsocketEvents(io)
      logger.info("Webserver started on \"" + process.env.MCONN_HOST + ":" + process.env.MCONN_PORT + "\"")
      logger.info("MConn \"" + process.env.npm_package_version + "\" is ready to rumble")
    catch error
      console.log error


module.exports = App
