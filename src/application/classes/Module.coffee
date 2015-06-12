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

async = require("async")
express = require("express")
fs = require("fs")
Q = require("q")
zookeeper = require("node-zookeeper-client")
require "colors"

Job = require("./Job")
logger = require("./Logger")("Module")

# Main class for all modules of mconn, must be extended in Moduleclasses
# The method descriptions will give you a hint how to use it, or use the Sample-Module as template
#
class Module

  #
  # Instance vars and Methods
  #

  # folder of the module
  folder: null

  # options of this module (initiated on init())
  options: null

  syncInProgress: false

  # queue of this module (initiated on init())
  queue: null

  # wrongwrite in child classes
  syncinterval: ->
    return process.env.MCONN_JOBQUEUE_SYNC_TIME

  # current running job
  currentJob: null

  # creates the module object
  #
  constructor: (@name, @active) ->
    @queue = async.queue @worker.bind(@)
    @logger = require("./Logger")("Module.#{@name}")
    @router = express.Router()
    unless typeof @cleanUpInventory is "function"
      logger.error("method 'cleanUpInventory' missing, sync process will NOT WORK", "Module.#{@name}")
    else unless process.env.MCONN_MARATHON_HOSTS
      logger.error("\"MCONN_MARATHON_HOSTS\" environment is missing, sync process will not work")
    else
      Q.delay(@syncinterval()).then =>
        @startSyncInterval()

  # sync module's inventory with marathon's inventory
  #
  # @return [Promise]
  #
  doSync: ->
    deferred = Q.defer()
    unless @syncInProgress
      @syncInProgress = true
      @pause()
      @compareWithMarathon()
      .then (result) =>
        @cleanUpInventory(result)
      .catch (error) =>
        @logger.error("Error on doSync(): " + error  + " " + error.stack)
      .finally =>
        @syncInProgress = false
        @resume()
        deferred.resolve()
    deferred.promise

  # start syncing interval, repeats sync-process every @syncInterval ms
  #
  startSyncInterval: ->
    @doSync().finally =>
      Q.delay(@syncinterval()).then =>
        @startSyncInterval()

  # get Inventory from marathon
  #
  # @return [Promise] resolves with marathon inventory object (created from api)
  #
  getMarathonInventory: ->
    deferred = Q.defer()
    # get marathon inventory
    request = require("request")
    options =
      url: "http://" + process.env.MCONN_MARATHON_HOSTS + "/v2/tasks?status=running"
      headers: {
        "Accept": "application/json"
        "Content-Type": "application/json"
      }
    request(options, (error, response, body) ->
      if error
        logger.error("Error fetching inventory from marathon: " + error)
        deferred.resolve(false)
      else
        deferred.resolve(JSON.parse(body))
    )
    deferred.promise

  # check if Task exists on marathon inventory
  #
  # @param [Object] moduleInventory
  # @param [String] taskId
  # @return [Boolean]
  #
  taskExistsInModuleInventory: (moduleInventory, taskId) ->
    for o in moduleInventory
      if taskId is o.data.jobData.data.fromMarathonEvent.taskId then return true
    return false #taskId not found in moduleInventory

  taskExistsInMarathonInventory: (marathonInventory, taskId) ->
    for m in marathonInventory.tasks
      if m.id is taskId then return true
    return false # not found

  # check if given task is queued or in Progress
  #
  # @param [Job] job to check
  # @return [Boolean]
  #
  taskIsQueuedOrInProgress: (job) ->
    alreadyInQueue = false
    for task in @queue.tasks
      if task.data.data.fromMarathonEvent.taskId is job.data.fromMarathonEvent.taskId
        @logger.debug("INFO", "Found missing job #{task.data.data.fromMarathonEvent.taskId} in jobqueue")
        alreadyInQueue = true
    if @currentJob and
    @currentJob.data.fromMarathonEvent.taskId is job.data.fromMarathonEvent.taskId and
    @currentJob.state isnt "finished" and
    @currentJob.state isnt "failed" and
    @currentJob.state isnt "nopreset"
      @logger.debug("INFO", "Found missing job #{@currentJob.data.fromMarathonEvent.taskId} on current modules worker")
      alreadyInQueue = true
    return alreadyInQueue

  # check if preset with given appId exists for this module
  #
  # @param [String] appId
  # @return [Promise] resolves with boolean
  #
  presetExistsInModule: (appId) ->
    deferred = Q.defer()
    ModulePreset = require("./ModulePreset")
    ModulePreset.getAllOfModule(@name).then (presets) ->
      moduleHasPreset = false
      for preset in presets
        if preset.appId is appId then moduleHasPreset = true
      deferred.resolve(moduleHasPreset)
    deferred.promise

  # get wrong tasks, that are missing on marathon inventory, but exist on local inventory
  #
  # @param [Object] marathonInventory current marathon inventory
  # @param [Object] moduleInventory inventory of this module
  # @return [Promise] resolving with array of wrong tasks
  #
  getWrongTasks: (marathonInventory, moduleInventory) =>
    deferred = Q.defer()
    wrong = []
    async.each moduleInventory, (task, done) =>
      unless @taskExistsInMarathonInventory(marathonInventory, task.data.jobData.data.fromMarathonEvent.taskId)
        job = Job.load(task.data.jobData.data, cleanupTask = true)
        if @taskIsQueuedOrInProgress(job)
          @logger.info "Job #{job.data.fromMarathonEvent.taskId} does not have to be cleaned up, since it already exists in current jobqueue"
          done()
        else
          @presetExistsInModule(job.data.fromMarathonEvent.appId).then (exists) =>
            unless exists
              @logger.debug("INFO","Ignoring job #{job.data.fromMarathonEvent.appId}, preset not found for module #{@name}")
            else
              wrong.push(job)
            done()
      else
        done()
    , =>
      for o in wrong
        @logger.info "\"" + o.data.fromMarathonEvent.taskId  + "\" is wrong on inventory for module \"#{@name}\"", "Module.#{@name}"
      deferred.resolve(wrong)
    deferred.promise

  # get missing tasks, that are missing on local inventory, but exist on marathon inventory
  #
  # @param [Object] marathonInventory current marathon inventory
  # @param [Object] moduleInventory inventory of this module
  # @return [Promise] resolving with array of missing tasks
  #
  getMissingTasks: (marathonInventory, moduleInventory) =>
    deferred = Q.defer()
    missing = []
    async.each marathonInventory.tasks, (task, done) =>
      unless @taskExistsInModuleInventory(moduleInventory, task.id)
        job = Job.createFromMarathonInventory(task, cleanupTask = true)
        if @taskIsQueuedOrInProgress(job)
          @logger.info "Job #{job.data.fromMarathonEvent.taskId} does not have to be cleaned up, since it already exists in current jobqueue"
          done()
        else
          @presetExistsInModule(job.data.fromMarathonEvent.appId).then (exists) =>
            unless exists
              @logger.debug("INFO","Ignoring job #{job.data.fromMarathonEvent.appId}, preset not found for module #{@name}")
            else
              missing.push(job)
            done()
      else
        done()
    , =>
      for m in missing
        @logger.info "\"" + m.data.fromMarathonEvent.taskId  + "\" is missing on inventory for module \"#{@name}\"", "Module.#{@name}"
      deferred.resolve(missing)
    deferred.promise

  # compare own inventory with marathon inventory and resolves the promise with an object of missing and wrong tasks
  #
  # @return [Promise] resolves with object {missing: [Job], wrong: [Job]}
  #
  compareWithMarathon: ->
    deferred = Q.defer()
    @logger.info("Starting Syncprocess", "Module.#{@name}")
    @pause()
    Job = require("./Job")
    marathonInventory = null
    moduleInventory = null
    wrongTasks = null
    missingTasks = null
    @getMarathonInventory()
    .then (MI) =>
      marathonInventory = MI
      @getInventory()
    .then (inventory) =>
      moduleInventory = inventory
      @getMissingTasks(marathonInventory, moduleInventory)
    .then (missing) =>
      missingTasks = missing
      @getWrongTasks(marathonInventory, moduleInventory)
    .then (wrong) ->
      wrongTasks = wrong
      deferred.resolve(
        wrong: wrongTasks
        missing: missingTasks
      )
    .catch (error) ->
      logger.error("Error syncing \"" + error + error.stack + "\"")
      deferred.resolve()
    deferred.promise

  # register router to use for webserver routing
  #
  registerRouter: ->
    app = require("../App").app
    app.use("/", @router)

  # get the current progress
  # to get this to work, you have to define and update doneActions and totalActions in subclass
  #
  getProgress: ->
    return {
      doneActions: @doneActions
      totalActions: @totalActions
    }

  # generates an relative path to use on the UI for this module
  #
  createModuleRoute: (path) ->
    return "/modules/#{@name}/#{path}"

  # get Websocket Handler, retry every second for 10 seconds, since it may happen, that the socket object
  # has not yet been created by mconn
  #
  # @return [Promise] resolves with socket.io object
  #
  getWebsocketHandler: ->
    deferred = Q.defer()
    counter = 0
    timer = setInterval ->
      app = require("../App").app
      unless app? then return
      else
        io = app.get("io")
        unless io?.sockets?
          counter++
          return
        else if counter > 10
          clearInterval(timer)
          logger.error("Websocket could not be opened, websocket functionality may be broken")
          deferred.resolve(false)
        else
          clearInterval(timer)
          deferred.resolve(io)
    , 1000
    deferred.promise

  # update Inventory on gui wrong websockets
  #
  # @param [Socket] socket optional socket to push to, if not submitted, update is pushed to all open sockets
  #
  updateInventoryOnGui: (socket) ->
    @getInventory()
    .then (inventory) =>
      unless socket then socket = require("../App").app.get("io").of("/#{@name}")
      socket.emit("update#{@name}Inventory", inventory)

  # get Inventory of module
  #
  # @return [Promise] resolves with inventory
  #
  getInventory: ->
    deferred = Q.defer()
    fullPath = "modules/" + @name + "/inventory"
    inventory = []
    zookeeperHandler = require("./ZookeeperHandler")
    zookeeperHandler.getChildren(fullPath)
    .then (children) ->
      async.each(children, (inventoryItem, done) ->
        zookeeperHandler.getData(fullPath + "/" + inventoryItem)
        .then (data) ->
          o = {
            path: inventoryItem
            data: data
          }
          inventory.push(o)
          done()
        .catch (error) ->
          logger.info("Error on getting inventory \"" + error + "\"")
          done()
      , ->
        deferred.resolve(inventory)
      )
    deferred.promise

  # get path of template
  #
  getTemplatePath: (templatename) ->
    path = require("path")
    return path.join(process.env.MCONN_MODULE_PATH , @folder, "templates", templatename)

  # send module's queue to client (browser)
  #
  WS_sendQueue: ->
    @getWebsocketHandler()
    .then (io) =>
      currentQueue = []
      MConnQueue = require("./JobQueue")
      if @currentJob and
      @currentJob.state isnt "finished" and
      @currentJob.state isnt "failed" and
      @currentJob.state isnt "nopreset" and
      taskForWebview = MConnQueue.processTaskForWebview({task: @currentJob})
        taskForWebview.runtime = MConnQueue.getRuntime(@currentJob)
        currentQueue.push(taskForWebview)

      for task in @queue.tasks
        currentQueue.push(MConnQueue.processTaskForWebview({task: task.data}))
      nsp = io.of("/" + @name)
      if io then nsp.emit("update#{@name}Queue",
        queue: currentQueue
        queuelength: @queue.length()
      )
    .catch (error) =>
      @logger.error("Error sending jobqueue to gui: " + error + error.stack)

  updatePresetsOnGui: (socket) ->
    unless socket
      app = require("../App").app
      io = app.get("io")
      socket = io.of("/" + @name)
    ModulePreset = require("./ModulePreset")
    ModulePreset.getAllOfModule(@name)
    .then (presets) ->
      socket.emit("updatePresets", presets)
    .catch (error) =>
      @logger.error("Error fetching presets: " + error)
      res.end()

  # init the module with everything it needs to work
  # this method should be extended like this
  # @example super(options).then -> YOUR STUFF
  # @param [Array] module options (ports paths etc)
  # @param [Express.Router] module router
  #
  init: (options = null, moduleRouter, folder) ->
    deferred = Q.defer()
    @folder = folder
    # set default route
    if moduleRouter
      moduleRouter.get(@createModuleRoute("main"), (req, res) =>
        if req.query.flush then cache = false else cache = @name + "_" + "main"
        res.render(@getTemplatePath("main"),
          modulename: @name
          filename: cache
          active: @name # <- has to be set for gui functionality
          activeSubmenu: "main"
          config: JSON.stringify(@options)
          cache: cache
        )
      )
    @getWebsocketHandler().then (io) =>
      if io
        nsp = io.of("/" + @name)
        nsp.on("connection", (socket) =>
          @updatePresetsOnGui(socket)
        )
    # set route for queue
    if moduleRouter
      moduleRouter.get(@createModuleRoute("queue"), (req, res) =>
        if req.params.flush then cache = false else cache = @name + "_" + "queue"
        res.render(@getTemplatePath("queue"),
          modulename: @name
          filename: cache
          activeSubmenu: "queue"
          active: @name # <- has to be set for gui functionality
          cache: cache
        )
      )
    # set route for preset
    if moduleRouter
      moduleRouter.get(@createModuleRoute("presets"), (req, res) =>
        if req.params.flush then cache = false else cache = @name + "_" + "presets"
        ModulePreset = require("./ModulePreset")
        ModulePreset.getAllOfModule(@name)
        .then (presets) =>
          res.render(@getTemplatePath("presets"),
            modulename: @name
            filename: cache
            cache: cache
          )
        .catch (error) =>
          @logger.error("Error fetching presets: " + error)
          res.end()
      )
    # send modules queue to gui
    setInterval =>
      @WS_sendQueue()
    ,1000

    @options = options
    @timeout = if @timeout then @timeout
    else
      @logger.warn("No timeout defined for module \"#{@name}\", set to default value 5000ms")
      @timeout = 5000
    ZookeeperHandler = require("./ZookeeperHandler")
    #generate required zookeeper paths, if they don't yet exist
    ZookeeperHandler.createPathIfNotExist("modules")
    .then => ZookeeperHandler.createPathIfNotExist("modules/" + @name)
    .then => ZookeeperHandler.createPathIfNotExist("modules/" + @name + "/presets") #all presets for marathon apps are stored here (filled by the ModulePreset)
    .then => ZookeeperHandler.createPathIfNotExist("modules/" + @name + "/jobqueue") #all jobs of the queue are registered here and removed if all modules are finished
    .then => ZookeeperHandler.createPathIfNotExist("modules/" + @name + "/inventory") #stores all states of the module like inventory or something else
    .then ->
      deferred.resolve()
    .catch (error) =>
      @logger.error(error.toString(), error.stack)
    return deferred.promise

  # add data to Zookeeper
  #
  # @param [String] relative path, module namespace modules/@name/inventory/ will be prepended
  # @param [Object] data data to push to zookeeper node
  #
  addToZKInventory: (path, customData, job) ->
    fullPath = "modules/" + @name + "/inventory/" + path
    dataToStore =
      customData: customData
      jobData: job

    logger.debug("INFO", "Create inventory \"" + JSON.stringify(dataToStore) + "\" on node \"#{fullPath}\"")
    zookeeperHandler = require("./ZookeeperHandler")
    return zookeeperHandler.createNode(fullPath, JSON.stringify(dataToStore))

  removeFromZKInventory: (path) ->
    fullPath = "modules/" + @name + "/inventory/" + path
    zookeeperHandler = require("./ZookeeperHandler")
    return zookeeperHandler.remove(fullPath)

  # add a job to the queue
  #
  # @param [Job] object, that holds all information about the incoming job from marathon
  # @param [callback] method to be called when everything is finished, callback MUST BE
  # CALLED ALLWAYS, since the main job waits for it as the signal, that the module has finished work
  #
  addJob: (job, callback) ->
    job.state = "idle"
    @logger.info("Job \"#{job.data.fromMarathonEvent.taskId}_#{job.data.fromMarathonEvent.taskStatus}\" created on jobqueue")
    Module.zookeeperHandler().exists("modules/#{@name}/jobqueue/" + job.data.fromMarathonEvent.taskId + "_" + job.data.fromMarathonEvent.taskStatus)
    .then (exists) =>
      unless exists #do not create zookeeper node for cleanup jobs
        if job.cleanup then promise = Q.resolve()
        else
          promise = Module.zookeeperHandler().createNode("modules/#{@name}/jobqueue/" + job.data.fromMarathonEvent.taskId + "_" + job.data.fromMarathonEvent.taskStatus,
            new Buffer(JSON.stringify({state: "new"})),
            zookeeper.ACL.OPEN, zookeeper.CreateMode.PERSISTENT)
      else
        promise = Q.resolve()
      return promise
    .then =>
      # add task in front of queue if it is a cleanup task
      if job.cleanup then @queue.unshift(job, callback) else @queue.push(job, callback)
    .catch (error) =>
      logger.error("Could not add job to module's queue \"" + error.toString() + "\"", "Module.#{@name}")

  # pause the queue to do sync or anything else, the current job will be processed till end, but no new job will be processed
  # until resume is not called
  #
  pause: ->
    logger.info("Pausing the job queue and waiting for empty jobworker", "Module.#{@name}.Queue")
    @queue.pause()

  # resumes the queue
  #
  resume: ->
    logger.info("Resuming queue", "Module.#{@name}.Queue")
    @queue.resume()

  # main method to work with every element of the queue, main logic of the modules lies here
  # - must be wrongwritten in child instances but must also call the super method
  # - checks, if the job has already been finished by this module
  # @example super(job,callback).then -> MODULES STUFF
  #
  worker: (job, callback) ->
    deferred = Q.defer()
    job.start = new Date().getTime()
    job.state = "started"
    @currentJob = job
    require("./JobQueue").WS_SendAllJobs()
    setTimeout =>
      unless job.state is "finished" or job.state is "failed" or job.state is "nopreset"
        @failed(job, callback, "timeout on job")
    , @timeout
    if job.cleanup #there is no zookeepernode for cleanup jobs
      deferred.resolve(false)
    else
      Module.zookeeperHandler().getData("modules/#{@name}/jobqueue/" + job.data.fromMarathonEvent.taskId + "_" + job.data.fromMarathonEvent.taskStatus)
      .then (data) ->
        if (data.state is "success" or data.state is "failed" or data.state is "nopreset")
          allreadyDoneState = data.state
        else
          allreadyDoneState = false
        deferred.resolve(allreadyDoneState)
      .catch (error) ->
        console.log(error)
    deferred.promise

  # finish job
  #
  # @param [String] state
  # @param [Job] job
  # @param [Function] callback worker callback
  # @param [String] reason optional reason if job has failed
  #
  finishJob: (state, job, callback, reason = false) ->
    unless job.state is "finished" or job.state is "failed" or job.state is "nopreset" #prevent from recalling if state is already finished
      @logger.debug("INFO", "Set job \"#{job.data.fromMarathonEvent.taskId}_#{job.data.fromMarathonEvent.taskStatus}\" to state \"#{state}\"")
      job.state = state
      job.stop = new Date().getTime()
      if job.cleanup
        callback() # do nothing
        #@currentJob = null
      else
        Module.zookeeperHandler().setData("modules/#{@name}/jobqueue/" + job.data.fromMarathonEvent.taskId + "_" + job.data.fromMarathonEvent.taskStatus, {state: state})
        .then =>
          message = "Job \"#{job.data.fromMarathonEvent.taskId}_#{job.data.fromMarathonEvent.taskStatus}\" state changed to #{state}! Job Queue is now \"" + @queue.length() + "\""
          if reason then message += " Reason: #{reason}"
          logger.info("Job \"#{job.data.fromMarathonEvent.taskId}_#{job.data.fromMarathonEvent.taskStatus}\" state changed to #{state}! Job Queue is now \"" + @queue.length() +
            "\"", "Module.#{@name}")
        .catch (error) =>
          logger.error("Could not change the job-state of \"#{job.data.fromMarathonEvent.taskId}_#{job.data.fromMarathonEvent.taskStatus}\" to #{state}",
            "Module.#{@name} \"" + error.toString() + "\"")
        .finally ->
          require("./JobQueue").WS_SendAllJobs()
          callback()
          #@currentJob = null

  # method to be called, if a module has successfully finished work
  # <strong> this module has to be called manually from child class </strong>
  #
  # @param [Job] object, that holds all information about the incoming job from marathon
  # @param [callback] method to be called when everything is finished
  #
  success: (job, callback ) ->
    @finishJob("finished", job, callback)

  # method to be called, if a module has failed finishing work
  # <strong> this module has to be called manually from child class </strong>
  #
  # @param [Job] object, that holds all information about the incoming job from marathon
  # @param [callback] method to be called when everything is finished
  #
  failed: (job, callback, reason = "") ->
    @finishJob("failed", job, callback, reason)

  # method to be called, if a module has failed finishing work
  # <strong> this module has to be called manually from child class </strong>
  #
  # @param [Job] object, that holds all information about the incoming job from marathon
  # @param [callback] method to be called when everything is finished
  #
  noPreset: (job, callback, reason = "") ->
    @finishJob("nopreset", job, callback, reason)

  # method to be called, if a module has allready done
  # <strong> this module has to be called manually from child class </strong>
  #
  # @param [Job] object, that holds all information about the incoming job from marathon
  # @param [callback] method to be called when everything is finished
  #
  allreadyDone: (job, callback) ->
    unless job.state is "finished" or job.state is "nopreset" or job.state is "failed" #prevent from recalling if state is already finished
      @logger.info("Setting job \"#{job.data.fromMarathonEvent.taskId}_#{job.data.fromMarathonEvent.taskStatus}\" to state \"finished\"")
      job.state = "finished"
      job.stop = new Date().getTime()
      logger.warn("Job allready done, skipping in queue! Job Queue is now \"" + @queue.length() + "\"", "Module.#{@name}")
      require("./JobQueue").WS_SendAllJobs()
      #@currentJob = null
      callback()

  #
  # STATICS FOR ALL MODULES
  #

  @allModulesLoadedDeferred: Q.defer()

  #zookeeper handler to comunicate with zookeeper
  @zookeeperHandler: ->
    require("./ZookeeperHandler")

  # checks, if a module is enabled
  #
  # @param [String] name of the module
  #
  @isEnabled: (modulename) ->
    enabled = false
    for name, module of @modules
      if name is modulename
        enabled = true
    return enabled

  # compile coffeescript in module
  #
  # @param [String] modulename
  #
  @compileCoffeescript: (modulename, folder) ->

    #todo, skip this, if MCONN_MODULE_PREPARE is false

    deferred = Q.defer()
    path = require("path")
    exec = require('child_process').exec
    exec("coffee -c " + path.join(process.env.MCONN_MODULE_PATH , folder), (error, stdout, stderr) ->
      if error
        logger.error("Error installing dependencies for module \"#{modulename}\", \"" + error + "\"")
      else
        logger.info("Successfully installed dependencies for module \"#{modulename}\"")
      deferred.resolve()
    )
    deferred.promise

  @appendModuleJavascripts: (modulename, folder) ->
    path = require("path")
    config = require("../webserver/config/config")
    javascriptsFolder = path.join(process.env.MCONN_MODULE_PATH , folder, "templates", "public")
    files = fs.readdirSync( javascriptsFolder )
    for f in files
      parts = f.split(".")
      if parts.length > 1 and parts[parts.length - 1] is "js"
        config.extraJavascriptFiles.push(modulename + "/" + f)

  # installs node modules from npm package.json dependencies for a module
  #
  # @param [String] modulename
  #
  @installNodeModules: (modulename, folder) ->
    deferred = Q.defer()
    path = require("path")
    exec = require('child_process').exec
    exec("cd " + path.join(process.env.MCONN_MODULE_PATH , folder) + " && npm install", (error, stdout, stderr) ->
      if error
        logger.error("Error compiling coffee for module \"#{modulename}\", " + error + "\"")
      else
        logger.info("Successfully compiled coffee for module \"#{modulename}\"")
      deferred.resolve()
    )
    deferred.promise

  # loads all modules for this application
  #
  @loadModules: (moduleRouter, expressStatics) ->
    deferred = Q.defer()
    path = require("path")
    try
      folders = fs.readdirSync( process.env.MCONN_MODULE_PATH )
      modules = new Object()
      modulesToLoad = process.env.MCONN_MODULE_START.split(",")
      async.each(folders, (folder, done) ->
        logger.debug("INFO","Found \"" + folder + "\"")
        found = false
        for module in modulesToLoad
          do (module, folder) ->
            if module is folder
              found = true
              if (fs.existsSync(process.env.MCONN_MODULE_PATH + "/#{folder}/package.json"))
                pjson = fs.readFileSync(process.env.MCONN_MODULE_PATH + "/#{folder}/package.json")
                moduleNameInPackageJson = JSON.parse(pjson).name
                logger.debug("INFO", "modulename from package.json of folder \"#{folder}\" is #{moduleNameInPackageJson}")
                logger.debug("INFO", "Initiating \"" + moduleNameInPackageJson + "\" from folder \"#{path.join(process.env.MCONN_MODULE_PATH , folder)}\"")
                Module.installNodeModules(moduleNameInPackageJson, folder)
                .then ->
                  Module.compileCoffeescript(moduleNameInPackageJson, folder)
                .then ->
                  Module.appendModuleJavascripts(moduleNameInPackageJson, folder)
                  #add statics to load css/js file in frontend
                  expressStatics[moduleNameInPackageJson] = path.join(process.env.MCONN_MODULE_PATH, folder, "templates", "public")
                  Module = require(path.join(process.env.MCONN_MODULE_PATH , folder))
                  config = require(path.join(process.env.MCONN_MODULE_PATH , folder + "/config.json"))
                  unless config?
                    logger.error("Error reading config for \"#{module}\", path \"" + path.join(process.env.MCONN_MODULE_PATH , folder + "/config.json\""))
                    done()
                  else
                    modules[moduleNameInPackageJson] = new Module()
                    modules[moduleNameInPackageJson].init(config, moduleRouter, folder)
                    .then ->
                      logger.info("Module \"" + moduleNameInPackageJson + "\" successfully initiated from folder \"#{folder}\"")
                    .catch (error) ->
                      logger.error("Module \"" + moduleNameInPackageJson + "\" could not be initiated \"" + error + "\"")
                    .finally ->
                      done()
                .catch (error) ->
                  console.log(error, error.stack)
                  done()
              else
                logger.error("package.json is missing in folder #{folder}, module could not be detected")
                done()
        unless found
          logger.debug("INFO", "Folder \"" + folder + "\" is present, but is no module or not activated by environment variable \"MCONN_MODULE_START\"")
          done()
      , =>
        @modules = modules
        @allModulesLoadedDeferred.resolve()
        logger.debug("INFO", "All modules loaded")
        deferred.resolve(modules)
      )
    catch error
      console.log error, error.stack
    deferred.promise

  # load the preset from zookeeper for this application
  #
  @loadPresetForModule: (appid, moduleName) ->
    clearedAppId = appid.split("/")[1]
    logger.debug("INFO", "\"" + moduleName + "\" is loading preset for appId \"#{clearedAppId}\"")
    deferred = Q.defer()
    this.zookeeperHandler().exists("modules/" + moduleName + "/presets/" + clearedAppId)
    .then (exists) =>
      if (exists)
        this.zookeeperHandler().getData("modules/" + moduleName + "/presets/" + clearedAppId)
        .then (config) ->
          deferred.resolve(config)
        .catch (error) ->
          logger.error "Error fetching app for \"" + clearedAppId + "\" for module \"" + moduleName + "\" \"" +  error + "\""
          deferred.resolve(false)
      else
        logger.debug "WARN", "Could not find preset for app \"" + clearedAppId + "\" for module \"" + moduleName + "\""
        deferred.resolve(false)
    .catch (error) ->
      logger.error "Error occured loading preset for app \"" + clearedAppId + "\" for module \"" + moduleName + "\" \"" +  error + "\""
      deferred.resolve(false)
    return deferred.promise
module.exports = Module
