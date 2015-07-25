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
fs = require("fs")
router = express.Router()
Q = require("q")

logger = require("../../classes/Logger")("IndexRouter")

# Angular Routes

# GET /
router.get "/", (req, res) ->
  if req.params.flush then cache = false else cache = "home"
  res.render("layout",
    filename: cache
    modulename: "home"
    cache: cache
  )
  res.end()

# GET /queue
router.get "/queue", (req, res) ->
  if req.params.flush then cache = false else cache = "queue"
  res.render("queue",
    filename: cache
    modulename: "home"
    cache: cache
  )
  res.end()

# WebAPI Routes

# GET /v1/queue
router.get "/v1/queue", (req, res) ->
  QueueManager = require("../../classes/QueueManager")
  res.json(QueueManager.createTaskDataForWebview())
  res.end()

# GET /v1/module/inventory/{moduleName}
router.get "/v1/module/inventory/:modulename", (req, res) ->
  modules = require("../../classes/Module").modules
  if req.params.modulename? isnt true or modules[req.params.modulename]? isnt true
    res.statusCode = 404
    res.json(
      status: "error"
      message: "Module not found: " + req.params.modulename
    )
    res.end()
  else
    module = modules[req.params.modulename]
    module.getInventory()
    .then (inventory) ->
      res.json(inventory)
    .catch (error) ->
      res.json(
        status: "error"
        message: error
      )
      res.end()

# GET /v1/module/list - list all modules and her settings
router.get "/v1/module/list", (req, res) ->
  modules = require("../../classes/Module").modules
  moduleList = {}
  filter = [
    "name"
    "logger"
    "timeout"
    "options"
    "folder"
  ]
  for name, module of modules
    o = {}
    for attribute in filter
      o[attribute] = module[attribute]
    moduleList[name] = o
  res.json(moduleList)
  res.end()

# GET /v1/module/list/{moduleName} - list selected module and her stats/config
router.get "/v1/module/list/:modulename", (req, res) ->
  modules = require("../../classes/Module").modules
  filter = [
    "name"
    "logger"
    "timeout"
    "options"
    "folder"
  ]
  if modules[req.params.modulename]?
    o = {}
    for attribute in filter
      o[attribute] = modules[req.params.modulename][attribute]
    res.json(o)
  else
    res.statusCode = 404
    res.json(
      status: "error"
      message: "Module not found: " + req.params.modulename
    )
  res.end()

# GET /v1/module/queue/list/{moduleName} - list tasks on selected module queue
router.get "/v1/module/queue/list/:modulename", (req, res) ->
  modules = require("../../classes/Module").modules
  if modules[req.params.modulename]?
    res.json(modules[req.params.modulename].getFullQueue())
  else
    res.statusCode = 404
    res.json(
      status: "error"
      message: "Module not found: " + req.params.modulename
    )
  res.end()

# POST /v1/module/queue/pause/{moduleName} - stop queue of selected module
router.post "/v1/module/queue/pause/:modulename", (req, res) ->
  modules = require("../../classes/Module").modules
  if modules[req.params.modulename]?
    modules[req.params.modulename].pause()
    res.json(modules[req.params.modulename])
  else
    res.statusCode = 404
    res.json(
      status: "error"
      message: "Module not found: " + req.params.modulename
    )
  res.end()

# POST /v1/module/queue/resume/{moduleName} - resume queue of selected module
router.post "/v1/module/queue/resume/:modulename", (req, res) ->
  modules = require("../../classes/Module").modules
  if modules[req.params.modulename]?
    modules[req.params.modulename].resume()
    res.json(modules[req.params.modulename])
  else
    res.statusCode = 404
    res.json(
      status: "error"
      message: "Module not found: " + req.params.modulename
    )
  res.end()

# GET /v1/module/preset - get all presets
router.get "/v1/module/preset", (req, res) ->
  ModulePreset = require("../../classes/ModulePreset")
  ModulePreset.getAll()
  .then (presets) ->
    res.json(presets)
  .catch (error) ->
    logger.error("GET on /preset " + error.toString(), "router.get preset", error.stack)
    res.statusCode = 500
  .finally ->
    res.end()

# GET /v1/module/preset/{moduleName} - all presets of selected module
router.get "/v1/module/preset/:modulename", (req, res) ->
  ModulePreset = require("../../classes/ModulePreset")
  ModulePreset.getAllOfModule(req.params.modulename)
  .then (presets) ->
    res.json(presets)
  .catch (error) ->
    logger.error("GET on /preset " + error.toString(), "router.get preset", error.stack)
    res.statusCode = 404
    res.json(
      status: "error"
      message: "Module not found: " + req.params.modulename
    )
  .finally ->
    res.end()

# POST /v1/module/preset - post a new preset to presetstore
router.post "/v1/module/preset", (req, res) ->
  ModulePreset = require("../../classes/ModulePreset")
  preset = [req.body]
  ModulePreset.sync(
    ->
      Q.resolve(preset)
  , allwaysUpdate = true)
  .then (result) ->
    res.json(
      result
    )
  .catch (error) ->
    res.json(
      status: "error"
      message: error.toString()
    )
  .finally ->
    res.end()

# PUT /v1/module/preset - update a preset of a module
router.put "/v1/module/preset", (req, res) ->
  ModulePreset = require("../../classes/ModulePreset")
  preset = [req.body]
  ModulePreset.sync(
    ->
      Q.resolve(preset)
  , allwaysUpdate = true)
  .then (result) ->
    res.json(
      result
    )
  .catch (error) ->
    res.send(
      status: "error"
      result: error
    )
  .finally ->
    res.end()

# DELETE /v1/module/preset - delete a preset of a module
router.delete "/v1/module/preset", (req, res) ->
  ModulePreset = require("../../classes/ModulePreset")
  if req.query?.moduleName? and req.query?.appId?
    preset = [
      moduleName: req.query.moduleName
      appId: req.query.appId
    ]
  else
    preset = [req.body]
  ModulePreset.remove(preset)
  .then (result) ->
    res.send(result)
  .catch (error) ->
    res.statusCode = 404
    logger.error("DELETE on /preset: " + error, "router.delete /preset", error.stack)
  .finally ->
    res.end()

# POST /v1/module.sync - for forcing sync
router.post "/v1/module/sync/:modulename?", (req, res) ->
  modules = require("../../classes/Module").modules
  if req.params.modulename
    logger.info("Force sync of module \"#{req.params.modulename}\"!")
    if modules[req.params.modulename]?
      logger.info("Syncing \"#{modules[req.params.modulename].name}\"")
      inventoryIsAvailableDeferred = Q.defer()
      modules[req.params.modulename].doSync(inventoryIsAvailableDeferred)
      inventoryIsAvailableDeferred.promise
      .then ->
        res.json(
          status: "ok"
          message: "Force sync of module: " + req.params.modulename
        )
      .catch (error) ->
        res.json(
          status: "error"
          message: "Sync of module: " + req.params.modulename + " failed, inventories not ready"
        )
    else
      res.statusCode = 404
      res.json(
        status: "error"
        message: "Module not found: " + req.params.modulename
      )
    res.end()
  else
    logger.info("Force sync of all modules!")
    for modulename, module of modules
      do (module) ->
        logger.info("Syncing \"#{module.name}\"")
        module.doSync()
    res.json(
      status: "ok"
      message: "Force sync of all modules"
    )
    res.end()

# GET /v1/info - show leader + enviroments
router.get "/v1/info", (req, res) ->
  env = {}
  vars = require("../../App").env_vars
  for e in vars
    env[e.name] = process.env[e.name]
  res.json(
    leader: res.locals.mconnenv.masterdata.serverdata.ip + ":" + res.locals.mconnenv.masterdata.serverdata.port
    env: env
  )
  res.end()

# GET /v1/leader - show leaders host:port
router.get "/v1/leader", (req, res) ->
  res.json(
    leader: res.locals.mconnenv.masterdata.serverdata.ip + ":" + res.locals.mconnenv.masterdata.serverdata.port
  )
  res.end()

# GET /v1/ping - for healthchecks
router.get "/v1/ping", (req, res) ->
  res.send("pong")
  res.end()

# POST /v1/exit/leader -> Kill the leading master
router.post "/v1/exit/leader", (req, res) ->
  ZookeeperHandler = require("../../classes/ZookeeperHandler")
  ZookeeperHandler.getMasterData()
  .then (masterdata) ->
    request = require("request")
    res.json(
      status: "ok"
      message: "Exit leader: " + res.locals.mconnenv.masterdata.serverdata.ip + ":" + res.locals.mconnenv.masterdata.serverdata.port
    )
    request.post(masterdata.serverdata.serverurl + "/v1/exit/node")
    res.end()

# POST /v1/exit/node -> Kill the requested instance
router.post "/v1/exit/node", (req, res) ->
  res.json(
    status: "ok"
    message: "Exit node"
  )
  res.end()
  process.exit()

module.exports = router
