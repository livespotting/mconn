express = require("express")
fs = require("fs")
logger = require("../../classes/MConnLogger")("MConn.indexRouter")
Q = require("q")
router = express.Router()

registerWebsocketEvents = ->
  # start sending to websockets, if ws ready...
  app = require("../../App").app
  unless app? then return
  else
    io = app.get("io")
    unless io?.sockets?
      return
    else
      io.on("connection", (socket) ->
        require("./../../classes/MConnJobQueue").WS_SendAllJobs()
      )

setTimeout(registerWebsocketEvents, 1200)

# Web UI Routes
#

# GET / -> /jobqueue
router.get "/", (req, res) ->
  modules = require("../../classes/MConnModule").modules
  res.redirect('/jobqueue');
  res.end()

# GET /jobqueue ui
router.get "/jobqueue", (req, res) ->
  res.render("jobqueue",
    modulename: "home"
    mconnenv: req.mconnenv
  )
  res.end()

# Web API Routes
#

# GET /v1/jobqueue
router.get "/v1/jobqueue", (req, res) ->
  MConnJobQueue = require("../../classes/MConnJobQueue")
  res.json(MConnJobQueue.createJobDataForWebview())
  res.end()

# GET /v1/module/list - list all modules and her settings
router.get "/v1/module/list", (req, res) ->
  modules = require("../../classes/MConnModule").modules
  res.json(modules)
  res.end()

# GET /v1/module/list/{moduleName} - list selected module and her stats/config
router.get "/v1/module/list/:modulename", (req, res) ->
  modules = require("../../classes/MConnModule").modules
  if modules[req.params.modulename]?
    res.json(modules[req.params.modulename])
  else
    res.statusCode = 500
  res.end()

# GET /v1/module/jobqueue/pause/{moduleName} - stop jobqueue of selected module
router.post "/v1/module/jobqueue/pause/:modulename", (req, res) ->
  modules = require("../../classes/MConnModule").modules
  if modules[req.params.modulename]?
    logger.logInfo("APICALL: pause queue for #{req.params.modulename}" )
    modules[req.params.modulename].pause()
    res.json(modules[req.params.modulename])
  else
    res.statusCode = 500
  res.end()

# GET /v1/module/jobqueue/resume/{moduleName} - resume jobqueue of selected module
router.post "/v1/module/jobqueue/resume/:modulename", (req, res) ->
  modules = require("../../classes/MConnModule").modules
  if modules[req.params.modulename]?
    logger.logInfo("APICALL: resume queue for #{req.params.modulename}" )
    modules[req.params.modulename].pause()
    res.json(modules[req.params.modulename])
  else
    res.statusCode = 500
  res.end()

# GET /v1/module/preset - get all presets
router.get "/v1/module/preset", (req, res) ->
  MConnModulePreset = require("../../classes/MConnModulePreset")
  MConnModulePreset.getAll()
  .then (presets) ->
    res.json(presets)
  .catch (error) ->
    logger.logError("GET on /preset " + error.toString(), "router.get preset")
    res.statusCode = 500
  .finally ->
    res.end()

# GET /v1/module/preset/{moduleName} - all presets of selected module
router.get "/v1/module/preset/:modulename", (req, res) ->
  MConnModulePreset = require("../../classes/MConnModulePreset")
  MConnModulePreset.getAllOfModule(req.params.modulename)
  .then (presets) ->
    res.json(presets)
  .catch (error) ->
    logger.logError("GET on /preset " + error.toString(), "router.get preset")
    res.statusCode = 500
  .finally ->
    res.end()

# POST /v1/module/preset - post a new preset to presetstore
router.post "/v1/module/preset", (req, res) ->
  MConnModulePreset = require("../../classes/MConnModulePreset")
  try
    preset = [req.body]
    MConnModulePreset.sync(
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
  MConnModulePreset = require("../../classes/MConnModulePreset")
  try
    preset = [req.body]
    MConnModulePreset.sync(
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
  MConnModulePreset = require("../../classes/MConnModulePreset")
  preset = [req.body]
  MConnModulePreset.remove(preset)
  .then ->
    res.send("ok")
  .catch (error) ->
    res.statusCode = 500
    logger.logError("DELETE on /preset: " + error, "router.delete /preset")
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
  logger.logInfo("GET /v1/leader" )
  res.end()

# GET /v1/ping - for healthchecks
router.get "/v1/ping", (req, res) ->
  res.send("pong")
  logger.logInfo("GET /v1/ping" )
  res.end()

# GET /v1/exit/leader -> Kill the leading master
router.get "/v1/exit/leader", (req, res) ->
  MConnZookeeperHandler = require("../../classes/MConnZookeeperHandler")
  MConnZookeeperHandler.getMasterData().then (masterdata) ->
    request = require("request")
    console.log masterdata
    request(masterdata.serverdata.serverurl + "/v1/exit")
    res.end()

# GET /v1/exit/node -> Kill the requested instance
router.get "/v1/exit/node", (req, res) ->
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
