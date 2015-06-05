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
logger = require("../../classes/Logger")("MConn.indexRouter")
Q = require("q")
router = express.Router()


# Web UI Routes
#

# GET / -> /jobqueue
router.get "/", (req, res) ->
  modules = require("../../classes/Module").modules
  res.redirect('/jobqueue')
  res.end()

# GET /jobqueue ui
router.get "/jobqueue", (req, res) ->
  if req.params.flush then cache = false else cache = "jobqueue"
  res.render("jobqueue",
    filename: cache
    modulename: "home"
    mconnenv: req.mconnenv
    cache: cache
  )
  res.end()

# Web API Routes
#

# GET /v1/jobqueue
router.get "/v1/jobqueue", (req, res) ->
  JobQueue = require("../../classes/JobQueue")
  res.json(JobQueue.createJobDataForWebview())
  res.end()

# GET /v1/module/list - list all modules and her settings
router.get "/v1/module/list", (req, res) ->
  modules = require("../../classes/Module").modules
  res.json(modules)
  res.end()

# GET /v1/module/list/{moduleName} - list selected module and her stats/config
router.get "/v1/module/list/:modulename", (req, res) ->
  modules = require("../../classes/Module").modules
  if modules[req.params.modulename]?
    res.json(modules[req.params.modulename])
  else
    res.statusCode = 500
  res.end()

# POST /v1/module/jobqueue/pause/{moduleName} - stop jobqueue of selected module
router.post "/v1/module/jobqueue/pause/:modulename", (req, res) ->
  modules = require("../../classes/Module").modules
  if modules[req.params.modulename]?
    modules[req.params.modulename].pause()
    res.json(modules[req.params.modulename])
  else
    res.statusCode = 500
  res.end()

# POST /v1/module/jobqueue/resume/{moduleName} - resume jobqueue of selected module
router.post "/v1/module/jobqueue/resume/:modulename", (req, res) ->
  modules = require("../../classes/Module").modules
  if modules[req.params.modulename]?
    modules[req.params.modulename].resume()
    res.json(modules[req.params.modulename])
  else
    res.statusCode = 500
  res.end()

# GET /v1/module/preset - get all presets
router.get "/v1/module/preset", (req, res) ->
  ModulePreset = require("../../classes/ModulePreset")
  ModulePreset.getAll()
  .then (presets) ->
    res.json(presets)
  .catch (error) ->
    logger.error("GET on /preset " + error.toString(), "router.get preset")
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
    logger.error("GET on /preset " + error.toString(), "router.get preset")
    res.statusCode = 500
  .finally ->
    res.end()

# POST /v1/module/preset - post a new preset to presetstore
router.post "/v1/module/preset", (req, res) ->
  ModulePreset = require("../../classes/ModulePreset")
  try
    preset = [req.body]
    ModulePreset.sync(
      ->
        Q.resolve(preset)
    , allwaysUpdate = true)
    res.send("ok")
    res.end()
  catch error
    console.log(error)
    res.statusCode = 500
    res.end()

# PUT /v1/module/preset - update a preset of a module
router.put "/v1/module/preset", (req, res) ->
  ModulePreset = require("../../classes/ModulePreset")
  try
    preset = [req.body]
    ModulePreset.sync(
      ->
        Q.resolve(preset)
    , allwaysUpdate = true)
    res.send("ok")
    res.end()
  catch error
    console.log(error)
    res.statusCode = 500
    res.end()

# DELETE /v1/module/preset - delete a preset of a module
router.delete "/v1/module/preset", (req, res) ->
  ModulePreset = require("../../classes/ModulePreset")
  preset = [req.body]
  ModulePreset.remove(preset)
  .then ->
    res.send("ok")
  .catch (error) ->
    res.statusCode = 500
    logger.error("DELETE on /preset: " + error, "router.delete /preset")
  .finally ->
    res.end()

# GET /v1/info - show leader + enviroments
router.get "/v1/info", (req, res) ->
  env = {}
  vars = require("../../App").env_vars
  for e in vars
    env[e.name] = process.env[e.name]
  res.json(
    leader: req.mconnenv.masterdata.serverdata.ip + ":" + req.mconnenv.masterdata.serverdata.port
    env: env
  )
  res.end()

# GET /v1/leader - show leaders host:port
router.get "/v1/leader", (req, res) ->
  res.json(
    leader: req.mconnenv.masterdata.serverdata.ip + ":" + req.mconnenv.masterdata.serverdata.port
  )
  res.end()

# GET /v1/ping - for healthchecks
router.get "/v1/ping", (req, res) ->
  res.send("pong")
  res.end()

# POST /v1/exit/leader -> Kill the leading master
router.post "/v1/exit/leader", (req, res) ->
  ZookeeperHandler = require("../../classes/ZookeeperHandler")
  ZookeeperHandler.getMasterData().then (masterdata) ->
    request = require("request")
    request.post(masterdata.serverdata.serverurl + "/v1/exit/node")
    res.end()

# POST /v1/exit/node -> Kill the requested instance
router.post "/v1/exit/node", (req, res) ->
  res.end()
  process.exit()


#  TEMP FOR DEVELOPMENT
#

# test to simulate marathon inventory
router.get "/dev/exampleMarathonInventory", (req, res) ->
  fs = require("fs")
  fs.readFile("/application/src/tests/testfiles/exampleMarathonInventory.json", (err, result) ->
    res.json(JSON.parse(result.toString()))
  )

module.exports = router
