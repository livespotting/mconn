async = require("async")
express = require("express")
fs = require("fs")
logger = require("./MConnLogger")("MConnModule")
Q = require("q")
zookeeper = require("node-zookeeper-client")
require "colors"

MConnJob = require("./MConnJob")

# Main class for all modules of mconn, must be extended in Moduleclasses
# The method descriptions will give you a hint how to use it, or use the Sample-Module as template
#
class MConnModule

  # INSTANCE VARS AND METHODS
  #

  # folder of the module
  folder: null

  # options of this module (initiated on init())
  options: null

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
    @logger = require("./MConnLogger")("MconnModule.#{@name}")
    @router = express.Router()
    unless typeof @cleanUpInventory is "function"
      logger.logError("method 'cleanUpInventory' missing, sync process will NOT WORK", "MconnModule.#{@name}")
    else unless process.env.MCONN_MARATHON_HOSTS
      logger.logError("\"MCONN_MARATHON_HOSTS\" environment is missing, sync process will not work")
    else
      Q.delay(@syncinterval()).then =>
        @startSyncInterval()

  # sync module's inventory with marathon's inventory
  #
  # @return [Promise]
  #
  doSync: ->
    deferred = Q.defer()
    @pause()
    @compareWithMarathon()
    .then (result) =>
      @cleanUpInventory(result)
    .catch (error) =>
      @logger.logError("Error on doSync(): " + error  + " " + error.stack)
    .finally =>
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
    request(options, (error, response, body) =>
      if error
        logger.logError("Error fetching inventory from marathon: " + error)
        deferred.resolve(false)
      else
        deferred.resolve(JSON.parse(body))
    )
    deferred.promise

  # compare own inventory with marathon inventory and resolves the promise with an object of missing and wrong tasks
  #
  # @return [Promise] resolves with object {missing: [MConnJob], wrong: [MConnJob]}
  #
  compareWithMarathon: ->
    deferred = Q.defer()
    @logger.logInfo("Starting Syncprocess", "MConnModule.#{@name}")
    @pause()
    MConnJob = require("./MConnJob")
    marathonInventory = null
    availablePresets = null
    MConnModulePreset = require("./MConnModulePreset")
    MConnModulePreset.getAllOfModule(@name).then (presets) =>
      availablePresets = presets
      @getMarathonInventory()
    .then (MI) =>
      marathonInventory = MI
      @getInventory()
    .then (ownInventory) =>
      missing = []
      for m in marathonInventory.tasks
        do (m) =>
          found = false
          for o in ownInventory
            if m.id is o.data.jobData.data.fromMarathon.taskId then found = true
          unless found
            job = MConnJob.createFromMarathonInventory(m)
            job.cleanup = true
            alreadyInQueue = false
            for task in @queue.tasks
              if task.data.data.fromMarathon.taskId is job.data.fromMarathon.taskId
                @logger.debug("INFO", "Found missing job #{task.data.data.fromMarathon.taskId} in jobqueue")
                alreadyInQueue = true
            if (@currentJob and @currentJob.data.fromMarathon.taskId is job.data.fromMarathon.taskId)
              @logger.debug("INFO", "Found missing job #{@currentJob.data.fromMarathon.taskId} on modules worker")
              alreadyInQueue = true
            unless alreadyInQueue
              moduleHasPreset = false
              for preset in availablePresets
                if preset.appId is job.data.fromMarathon.appId then moduleHasPreset = true
              unless moduleHasPreset
                @logger.debug("INFO","Ignoring job #{job.data.fromMarathon.appId}, preset not found for module #{@name}")
              else
                missing.push(job)
            else
              @logger.logInfo "Job #{job.data.fromMarathon.taskId} does not have to be cleaned up, since it already exists in current jobqueue"
      for m in missing
        @logger.logInfo "\"" + m.data.fromMarathon.taskId  + "\" is missing on inventory for module \"#{@name}\"", "MConnModule.#{@name}"

      wrong = []
      for o in ownInventory
        do (o)=>
          found = false
          for m in marathonInventory.tasks
            if m.id is o.data.jobData.data.fromMarathon.taskId then found = true
          unless found
            job = MConnJob.load(o.data.jobData.data)
            job.cleanup = true
            alreadyInQueue = false
            for task in @queue.tasks
              if task.data.data.fromMarathon.taskId is job.data.fromMarathon.taskId
                @logger.debug("INFO", "Found wrong job \"#{task.data.data.fromMarathon.taskId}\"in queue")
                alreadyInQueue = true
            if (@currentJob and @currentJob.data.fromMarathon.taskId is job.data.fromMarathon.taskId)
              @logger.debug("INFO", "Found wrong job \"#{@currentJob.data.fromMarathon.taskId}\" on jobworker")
              alreadyInQueue = true
            unless alreadyInQueue
              wrong.push(job)
            else
              @logger.logInfo "Wrong job \"#{job.data.fromMarathon.taskId}\" does not have to be cleaned up, since it already exists in current jobqueue"
      for o in wrong
        @logger.logInfo "\"" + o.data.fromMarathon.taskId  + "\" is wrong on inventory for module \"#{@name}\"", "MConnModule.#{@name}"

      deferred.resolve(
        wrong: wrong
        missing: missing
      )
    .catch (error) ->
      logger.logError("Error syncing \"" + error + error.stack + "\"")
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

  # create an empty zookeeperPath if it not exists
  #
  # @todo this should be moved to zookeeper class
  # @param [String] path of the zookeeper node
  #
  createPathIfNotExist: (path) ->
    deferred = Q.defer()
    MConnModule.zookeeperHandler().exists(path)
    .then (exists) =>
      if (exists)
        return Q.resolve()
      else
        @logger.logInfo("Create node \"#{path}\"")
        return MConnModule.zookeeperHandler().createNode(path,new Buffer(""), zookeeper.ACL.OPEN, zookeeper.CreateMode.PERSISTENT)
    .then ->
      deferred.resolve()
    .catch (error) ->
      logger.logError("Error checking if path exists \"" + error + "\"")
      deferred.resolve()
    deferred.promise

  # generates an relative path to use on the UI for this module
  #
  createModuleRoute: (path)->
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
          logger.logError("Websocket could not be opened, websocket functionality may be broken")
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
  updateInventoryOnGui: (socket)->
    @getInventory()
    .then (inventory) =>
      @getWebsocketHandler().then (io)=>
        socketToSendTo = if socket then socket else io.sockets
        socketToSendTo.emit("update#{@name}Inventory", inventory)

  # get Inventory of module
  #
  # @return [Promise] resolves with inventory
  #
  getInventory: ->
    deferred = Q.defer()
    fullPath = "modules/" + @name + "/inventory"
    inventory = []
    zookeeperHandler = require("./MConnZookeeperHandler")
    zookeeperHandler.getChildren(fullPath)
    .then (children)->
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
          logger.logInfo("Error on getting inventory \"" + error + "\"")
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
        res.render(@getTemplatePath("main"),
          modulename: @name
          active: @name # <- has to be set for gui functionality
          activeSubmenu: "main"
          config: JSON.stringify(@options)
          mconnenv: req.mconnenv

        )
      )

    # set route for queue
    if moduleRouter
      moduleRouter.get(@createModuleRoute("queue"), (req, res) =>
        res.render(@getTemplatePath("queue"),
          modulename: @name
          activeSubmenu: "queue"
          active: @name # <- has to be set for gui functionality
          mconnenv: req.mconnenv
        )
      )

    # set route for queue
    if moduleRouter
      moduleRouter.get(@createModuleRoute("presets"), (req, res) =>
        MConnModulePreset = require("./MConnModulePreset")
        MConnModulePreset.getAllOfModule(@name)
        .then (presets) =>
          res.render(@getTemplatePath("presets"),
            modulename: @name
            activeSubmenu: "presets"
            presets: presets
            active: @name # <- has to be set for gui functionality
            mconnenv: req.mconnenv
          )
        .catch (error) =>
          @logger.logError("Error fetching presets: " + error)
          res.end()
      )


    # send modules queue to gui
    # emit an event every 1s
    setInterval =>
      @getWebsocketHandler()
      .then (io) =>
        currentQueue = []
        MConnQueue = require("./MConnJobQueue")
        if @currentJob
          taskForWebview = MConnQueue.processTaskForWebview({task:@currentJob})
          if taskForWebview
            taskForWebview.runtime = MConnQueue.getRuntime(@currentJob)
            currentQueue.push(taskForWebview)

        for task in @queue.tasks
          currentQueue.push(MConnQueue.processTaskForWebview({task:task.data}))
        if io then io.sockets.emit("update#{@name}Queue",
          queue: currentQueue
          queuelength: @queue.length()
        )
      .catch (error) =>
        @logger.logError("Error sending jobqueue to gui: " + error + error.stack)
    , 1000

    @options = options
    @timeout = if @timeout then @timeout
    else
      @logger.logWarn("No timeout defined for module \"#{@name}\", set to default value 5000ms")
      @timeout = 5000

    #generate required zookeeper paths, if they don't yet exist
    @createPathIfNotExist("modules")
    .then => @createPathIfNotExist("modules/" + @name)
    .then => @createPathIfNotExist("modules/" + @name + "/presets") #all presets for marathon apps are stored here (filled by the MConnModulePreset)
    .then => @createPathIfNotExist("modules/" + @name + "/jobqueue") #all jobs of the queue are registered here and removed if all modules are finished
    .then => @createPathIfNotExist("modules/" + @name + "/inventory") #stores all states of the module like inventory or something else
    .then ->
      deferred.resolve()
    .catch (error) =>
      @logger.logError(error.toString(), error.stack)
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
    zookeeperHandler = require("./MConnZookeeperHandler")
    return zookeeperHandler.createNode(fullPath, JSON.stringify(dataToStore))

  removeFromZKInventory: (path) ->
    fullPath = "modules/" + @name + "/inventory/" + path
    zookeeperHandler = require("./MConnZookeeperHandler")
    return zookeeperHandler.remove(fullPath)

  # add a job to the queue
  #
  # @param [MConnJob] object, that holds all information about the incoming job from marathon
  # @param [callback] method to be called when everything is finished, callback MUST BE
  # CALLED ALLWAYS, since the main job waits for it as the signal, that the module has finished work
  #
  addJob: (job, callback) ->
    job.state = "enqueued"
    @logger.logInfo("Job \"#{job.data.fromMarathon.taskId}_#{job.data.fromMarathon.taskStatus}\" created on jobqueue")
    MConnModule.zookeeperHandler().exists("modules/#{@name}/jobqueue/" + job.data.fromMarathon.taskId + "_" + job.data.fromMarathon.taskStatus)
    .then (exists) =>
      unless exists #do not create zookeeper node for cleanup jobs
        if job.cleanup then promise = Q.resolve()
        else
          promise = MConnModule.zookeeperHandler().createNode("modules/#{@name}/jobqueue/" + job.data.fromMarathon.taskId + "_" + job.data.fromMarathon.taskStatus,
            new Buffer(JSON.stringify({state: "new"})),
            zookeeper.ACL.OPEN, zookeeper.CreateMode.PERSISTENT)
      else
        promise = Q.resolve()
      return promise
    .then =>
      # add task in front of queue if it is a cleanup task
      if job.cleanup then @queue.unshift(job, callback) else @queue.push(job, callback)
    .catch (error) =>
      logger.logError("Could not add job to module's queue \"" + error.toString() + "\"", "MConnModule.#{@name}")

  # pause the queue to do sync or anything else, the current job will be processed till end, but no new job will be processed
  # until resume is not called
  #
  pause: ->
    logger.logInfo("Pausing the job queue and waiting for empty jobworker", "MConnModule.#{@name}.Queue")
    @queue.pause()

  # resumes the queue
  #
  resume: ->
    logger.logInfo("Resuming queue", "MConnModule.#{@name}.Queue")
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
    require("./MConnJobQueue").WS_SendAllJobs()
    setTimeout =>
      unless job.state is "finished" or job.state is "failed" or job.state is "nopreset"
        @failed(job, callback, "timeout on job")
    , @timeout
    if job.cleanup #there is no zookeepernode for cleanup jobs
      deferred.resolve(false)
    else
      MConnModule.zookeeperHandler().getData("modules/#{@name}/jobqueue/" + job.data.fromMarathon.taskId + "_" + job.data.fromMarathon.taskStatus)
      .then (data) ->
        if (data.state is "success" or data.state is "failed" or data.state is "nopreset")
          allreadyDoneState = data.state
        else
          allreadyDoneState = false
        deferred.resolve(allreadyDoneState)
      .catch (error) ->
        console.log(error)
    deferred.promise

  finishJob: (state, job, callback, reason = false) ->
    unless job.state is "finished" or job.state is "failed" or job.state is "nopreset" #prevent from recalling if state is already finished
      @logger.debug("INFO", "Set job \"#{job.data.fromMarathon.taskId}_#{job.data.fromMarathon.taskStatus}\" to state \"#{state}\"")
      job.state = state
      job.stop = new Date().getTime()
      if job.cleanup
        callback() # do nothing
        @currentJob = null
      else
        MConnModule.zookeeperHandler().setData("modules/#{@name}/jobqueue/" + job.data.fromMarathon.taskId + "_" + job.data.fromMarathon.taskStatus, {state: state})
        .then =>
          message = "Job \"#{job.data.fromMarathon.taskId}_#{job.data.fromMarathon.taskStatus}\" state changed to #{state}! Job Queue is now \"" + @queue.length() + "\""
          if reason then message += " Reason: #{reason}"
          logger.logInfo("Job \"#{job.data.fromMarathon.taskId}_#{job.data.fromMarathon.taskStatus}\" state changed to #{state}! Job Queue is now \"" + @queue.length() + "\"", "MconnModule.#{@name}")
        .catch (error) =>
          logger.logError("Could not change the job-state of \"#{job.data.fromMarathon.taskId}_#{job.data.fromMarathon.taskStatus}\" to #{state}", "MconnModule.#{@name} \"" + error.toString() + "\"")
        .finally =>
          require("./MConnJobQueue").WS_SendAllJobs()
          callback()
          @currentJob = null

  # method to be called, if a module has successfully finished work
  # <strong> this module has to be called manually from child class </strong>
  #
  # @param [MConnJob] object, that holds all information about the incoming job from marathon
  # @param [callback] method to be called when everything is finished
  #
  success: (job, callback ) ->
    @finishJob("finished", job, callback)

  # method to be called, if a module has failed finishing work
  # <strong> this module has to be called manually from child class </strong>
  #
  # @param [MConnJob] object, that holds all information about the incoming job from marathon
  # @param [callback] method to be called when everything is finished
  #
  failed: (job, callback, reason = "") ->
    @finishJob("failed", job, callback, reason)

  # method to be called, if a module has failed finishing work
  # <strong> this module has to be called manually from child class </strong>
  #
  # @param [MConnJob] object, that holds all information about the incoming job from marathon
  # @param [callback] method to be called when everything is finished
  #
  noPreset: (job, callback, reason = "") ->
    @finishJob("nopreset", job, callback, reason)

  # method to be called, if a module has allready done
  # <strong> this module has to be called manually from child class </strong>
  #
  # @param [MConnJob] object, that holds all information about the incoming job from marathon
  # @param [callback] method to be called when everything is finished
  #
  allreadyDone: (job, callback) ->
    unless job.state is "finished" or job.state is "nopreset" or job.state is "failed" #prevent from recalling if state is already finished
      @logger.logInfo("Setting job \"#{job.data.fromMarathon.taskId}_#{job.data.fromMarathon.taskStatus}\" to state \"finished\"")
      job.state = "finished"
      job.stop = new Date().getTime()
      logger.logWarn("Job allready done, skipping in queue! Job Queue is now \"" + @queue.length() + "\"", "MconnModule.#{@name}")
      require("./MConnJobQueue").WS_SendAllJobs()
      @currentJob = null
      callback()

  #
  # STATICS FOR ALL MODULES
  #

  @allModulesLoadedDeferred: Q.defer()

  #zookeeper handler to comunicate with zookeeper
  @zookeeperHandler: ->
    require("./MConnZookeeperHandler")

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
        logger.logError("Error installing dependencies for module \"#{modulename}\", \"" + error + "\"")
      else
        logger.logInfo("Successfully installed dependencies for module \"#{modulename}\"")
      deferred.resolve()
    )
    deferred.promise

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
        logger.logError("Error compiling coffee for module \"#{modulename}\", " + error + "\"")
      else
        logger.logInfo("Successfully compiled coffee for module \"#{modulename}\"")
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
                MConnModule.installNodeModules(moduleNameInPackageJson, folder)
                .then ->
                  MConnModule.compileCoffeescript(moduleNameInPackageJson, folder)
                .then ->
                  #add statics to load css/js file in frontend
                  expressStatics[moduleNameInPackageJson] = path.join(process.env.MCONN_MODULE_PATH, folder, "templates", "public")
                  Module = require(path.join(process.env.MCONN_MODULE_PATH , folder))
                  config = require(path.join(process.env.MCONN_MODULE_PATH , folder + "/config.json"))
                  unless config?
                    logger.logError("Error reading config for \"#{module}\", path \"" + path.join(process.env.MCONN_MODULE_PATH , folder + "/config.json\""))
                    done()
                  else
                    modules[moduleNameInPackageJson] = new Module()
                    modules[moduleNameInPackageJson].init(config, moduleRouter, folder)
                    .then ->
                      logger.logInfo("Module \"" + moduleNameInPackageJson + "\" successfully initiated from folder \"#{folder}\"")
                    .catch (error) ->
                      logger.logError("Module \"" + moduleNameInPackageJson + "\" could not be initiated \"" + error + "\"")
                    .finally ->
                      done()
                .catch (error) ->
                  console.log(error, error.stack)
                  done()
              else
                logger.logError("package.json is missing in folder #{folder}, module could not be detected")
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
          logger.logError "Error fetching app for \"" + clearedAppId + "\" for module \"" + moduleName + "\" \"" +  error + "\""
          deferred.resolve(false)
      else
        logger.debug "WARN", "Could not find preset for app \"" + clearedAppId + "\" for module \"" + moduleName + "\""
        deferred.resolve(false)
    .catch (error) ->
      logger.logError "Error occured loading preset for app \"" + clearedAppId + "\" for module \"" + moduleName + "\" \"" +  error + "\""
      deferred.resolve(false)
    return deferred.promise

  # handle errors with modules
  #
  # @todo: this seems to be unused now, needs a check
  #
  @moduleErrorHandler: (error) ->
    logger.debug("INFO", "\"" + moduleName + "\"")
    logger.logError(error)

module.exports = MConnModule
