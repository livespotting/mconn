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
_ = require("underscore")

logger = require("./Logger")("Module")
TaskData = require("./TaskData")

# Main class for all modules of mconn, must be extended in Moduleclasses
# The method descriptions will give you a hint how to use it, or use the Sample-Module as template
#
class Module

  #
  # Instance vars and Methods
  #

  # loaded modules
  @modules: []

  # folder of the module
  folder: null

  # options of this module (initiated on init())
  options: null

  syncInProgress: false

  # presets
  presets: null

  # queue of this module (initiated on init())
  queue: null

  checkIntervalPauseQueue: 100

  # wrongwrite in child classes
  syncinterval: ->
    return process.env.MCONN_MODULE_SYNC_TIME

  # active Task
  activeTask: null

  # creates the module object
  #
  constructor: (@name, @active) ->
    @queue = async.queue @worker.bind(@)
    @logger = require("./Logger")("Module.#{@name}")
    @router = express.Router()
    @presets = []
    unless typeof @cleanUpInventory is "function"
      logger.error("Method \"cleanUpInventory\" is missing, sync process will not work", "")
    else unless process.env.MCONN_MARATHON_HOSTS
      logger.error("\"MCONN_MARATHON_HOSTS\" environment is missing, sync process will not work", "")
    else
      Q.delay(@syncinterval())
      .then =>
        @startSyncInterval()
      .catch (error) =>
        @logger.error(error, error.stack)

  getPreset: (appId) ->
    for index, p of @presets
      if p.appId is appId
        return p
    return false #not found

  editPreset: (preset) ->
    for index, p of @presets
      if p.appId is preset.appId
        @presets[index] = preset
        @logger.debug("INFO", "Successfully edited preset \"#{preset.appId}\" from cache")

  createPreset: (preset) ->
    @presets.push(preset)
    @logger.debug("INFO", "Successfully added preset \"#{preset.appId}\" to cache")

  deletePreset: (preset) ->
    for index, p of @presets
      if p.appId is preset.appId
        @presets.splice(index, 1)
        @logger.debug("INFO", "Successfully removed preset \"#{preset.appId}\" from cache")

  # sync module's inventory with marathon's inventory
  #
  # @return [Promise]
  #
  doSync: (inventoriesAvailableDeferred = false) ->
    deferred = Q.defer()
    ZookeeperHandler = Module.getZookeeperHandler()
    if @syncInProgress or ZookeeperHandler.isMaster isnt true
      deferred.resolve()
    else
      @syncInProgress = true
      @pause()
      .then =>
        @compareWithMarathon()
      .then (result) =>
        if inventoriesAvailableDeferred then inventoriesAvailableDeferred.resolve()
        @cleanUpInventory(result)
      .catch (error) =>
        if inventoriesAvailableDeferred then inventoriesAvailableDeferred.reject()
        @logger.error("Could not proceed inventory sync, because Marathon is unreachable!")
        @logger.debug("ERROR", "doSync(): " + error  + " ", error.stack)
      .finally =>
        @syncInProgress = false
        @resume()
        deferred.resolve()
    deferred.promise

  # start syncing interval, repeats sync-process every @syncInterval ms
  #
  startSyncInterval: ->
    setInterval =>
      @doSync()
    , @syncinterval()

  # get Inventory from marathon
  #
  # @return [Promise] resolves with marathon inventory object (created from api)
  #
  getMarathonInventory: ->
    @logger.info("Fetching Marathon Inventory")
    inventory = null
    request = require "request"
    deferred = Q.defer()
    hosts = process.env.MCONN_MARATHON_HOSTS.split(",")
    async.eachSeries hosts,
      (host, done) =>
        if inventory
          @logger.debug("INFO", "Skipping \"" + host + "\" because inventory has already been fetched")
          done()
          return
        else
          @logger.debug("INFO", "Checking if \"" + host + "\" is alive")
          unless process.env.MCONN_MARATHON_SSL is "true"
            options =
              url: "http://" + host + "/v2/tasks?status=running"
              headers: {
                "Accept": "application/json"
                "Content-Type": "application/json"
              }
          else
            options =
              url: "https://" + host + "/v2/tasks?status=running"
              headers: {
                "Accept": "application/json"
                "Content-Type": "application/json"
              }
              #ssl stuff to avoid errors on selfsigned certificates
              rejectUnauthorized: false
              requestCert: true
              agent: false
          request options, (error, response, body) =>
            if error
              @logger.debug("ERROR", "Could not fetch the inventory from Marathon Host \"#{options.url}\": " +  error, "")
              done()
            else
              try
                if body.length
                  inventory = JSON.parse(body)
                  @logger.debug("INFO", "Successfully fetched inventory from host \"" + host + "\"")
                done()
              catch error
                @logger.error("Could not fetch the inventory from Marathon Host " + host)
                done()
      , ->
        deferred.resolve(inventory)
    deferred.promise

  # check if Task exists on marathon inventory
  #
  # @param [Object] moduleInventory
  # @param [String] taskId
  # @return [Boolean]
  #
  taskExistsInModuleInventory: (moduleInventory, taskId) ->
    for o in moduleInventory
      taskData = TaskData.load(o.data.taskData)
      if taskId is taskData.getData().taskId then return true
    return false #taskId not found in moduleInventory

  taskExistsInMarathonInventory: (marathonInventory, taskId) ->
    for m in marathonInventory.tasks
      if m.id is taskId then return true
    return false # not found

  # check if given task is queued or in Progress
  #
  # @param [TaskData] taskData to check
  # @return [Boolean]
  #
  taskIsQueuedOrInProgress: (taskData) ->
    alreadyInQueue = false
    for asyncTask in @queue.tasks
      if asyncTask.data.getData().taskId is taskData.getData().taskId
        @logger.debug("INFO", "Found task \"#{asyncTask.data.getData().taskId}\" in queue")
        alreadyInQueue = true
    if @activeTask and
    @activeTask.getData().taskId is taskData.getData().taskId and
    @checkTaskHasFinishedState(@activeTask) isnt true
      @logger.debug("INFO", "Found task \"#{@activeTask.getData()}\" on active modules worker")
      alreadyInQueue = true
    return alreadyInQueue

  # check if preset with given appId exists for this module
  #
  # @param [String] appId
  # @return [Promise] resolves with boolean
  #
  presetExistsInModuleAndIsEnabled: (appId) ->
    deferred = Q.defer()
    ModulePreset = require("./ModulePreset")
    ModulePreset.getAllOfModule(@name)
    .then (presets) ->
      presetStatus = "not found"
      for preset in presets
        if preset.appId is appId
          if preset.status is "enabled"
            presetStatus = "ok"
          else
            presetStatus = "not enabled"
      deferred.resolve(presetStatus)
    .catch (error) =>
      @logger.error(error, error.stack)
    deferred.promise

  # get wrong tasks, that are missing on marathon inventory, but exist on local inventory
  #
  # @param [Object] marathonInventory active marathon inventory
  # @param [Object] moduleInventory inventory of this module
  # @return [Promise] resolving with array of wrong tasks
  #
  getWrongTasks: (marathonInventory, moduleInventory) =>
    @logger.debug("INFO", "Searching for wrong tasks")
    deferred = Q.defer()
    wrong = []
    async.each moduleInventory, (zkInventoryItem, done) =>
      taskData = TaskData.load(zkInventoryItem.data.taskData, cleanup = true)
      unless @taskExistsInMarathonInventory(marathonInventory, taskData.getData().taskId)
        if @taskIsQueuedOrInProgress(taskData)
          @logger.info "Task \"#{taskData.getData().taskId}\" does not have to be cleaned up, since it already exists in active queue"
          done()
        else
          @presetExistsInModuleAndIsEnabled(taskData.getData().appId)
          .then (presetStatus) =>
            if presetStatus is "not found"
              @logger.debug("INFO", "Ignoring wrong task \"#{taskData.getData().appId}\", preset not found for module \"#{@name}\"")
            else if presetStatus is "not enabled"
              @logger.debug("INFO", "Ignoring wrong task \"#{taskData.getData().appId}\", preset not enabled for module \"#{@name}\"")
            else
              taskData.cleanup = true
              wrong.push(taskData)
            done()
          .catch (error) =>
            @logger.error(error, error.stack)
      else
        done()
    , =>
      for taskData in wrong
        @logger.info "\"" + taskData.getData().taskId + "\" is wrong on inventory for module \"#{@name}\"", "Module.#{@name}"
      deferred.resolve(wrong)
    deferred.promise

  # get missing tasks, that are missing on local inventory, but exist on marathon inventory
  #
  # @param [Object] marathonInventory active marathon inventory
  # @param [Object] moduleInventory inventory of this module
  # @return [Promise] resolving with array of missing tasks
  #
  getMissingTasks: (marathonInventory, moduleInventory) =>
    @logger.debug("INFO", "Searching for missed tasks")
    deferred = Q.defer()
    missing = []
    async.each marathonInventory.tasks, (inventoryItem, done) =>
      taskData = TaskData.createFromMarathonInventory(inventoryItem, cleanup = true)
      unless @taskExistsInModuleInventory(moduleInventory, taskData.getData().taskId)
        if @taskIsQueuedOrInProgress(taskData)
          @logger.info "Task #{taskData.getData().taskId} does not have to be cleaned up, since it already exists in active queue"
          done()
        else
          @presetExistsInModuleAndIsEnabled(taskData.getData().appId)
          .then (presetStatus) =>
            if presetStatus is "not found"
              @logger.debug("INFO", "Ignoring missed task \"#{taskData.getData().appId}\", preset not found for module \"#{@name}\"")
            else if presetStatus is "not enabled"
              @logger.debug("INFO", "Ignoring missed task \"#{taskData.getData().appId}\", preset not enabled for module \"#{@name}\"")
            else
              taskData.cleanup = true
              missing.push(taskData)
            done()
          .catch (error) =>
            @logger.error(error, error.stack)
      else
        done()
    , =>
      for taskData in missing
        @logger.info "Task \"" + taskData.getData().taskId  + "\" is missing on inventory for module \"#{@name}\"", "Module.#{@name}"
      deferred.resolve(missing)
    deferred.promise

  # compare own inventory with marathon inventory and resolves the promise with an object of missing and wrong tasks
  #
  # @return [Promise] resolves with object {missing: [TaskData], wrong: [TaskData]}
  #
  compareWithMarathon: ->
    deferred = Q.defer()
    @logger.info("Starting Syncprocess", "Module.#{@name}")
    TaskData = require("./TaskData")
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
      logger.debug("ERROR", "Error syncing \"" + error + "\"", error.stack)
      deferred.resolve()
    deferred.promise

  # register router to use for webserver routing
  #
  registerRouter: ->
    app = require("../App").app
    app.use("/", @router)

  # get the active progress
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
    .catch (error) =>
      @logger.error error + error.stack

  # get Inventory of module
  #
  # @return [Promise] resolves with inventory
  #
  getInventory: ->
    deferred = Q.defer()
    fullPath = "modules/" + @name + "/inventory"
    inventory = []
    zookeeperHandler = Module.getZookeeperHandler()
    zookeeperHandler.getChildren(fullPath)
    .then (children) ->
      async.each(children, (inventoryItem, done) ->
        zookeeperHandler.getData(fullPath + "/" + inventoryItem)
        .then (data) ->
          o = {
            id: inventoryItem
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
    .catch (error) =>
      @logger.error error + error.stack
    deferred.promise

  # get path of template
  #
  getTemplatePath: (templatename) ->
    path = require("path")
    return path.join(process.env.MCONN_MODULE_PATH, @folder, "bin", "templates", templatename)

  getFullQueue: ->
    activeQueue = []
    QueueManager = require("./QueueManager")
    if @activeTask and
    @checkTaskHasFinishedState(@activeTask) isnt true and
    taskForWebview = QueueManager.processTaskForWebview(@activeTask)
      taskForWebview.runtime = QueueManager.getRuntime(@activeTask)
      activeQueue.push(taskForWebview)
    for task in @queue.tasks
      activeQueue.push(QueueManager.processTaskForWebview(task.data))
    return activeQueue

  # send module's queue to client (browser)
  #
  WS_sendQueue: ->
    @getWebsocketHandler()
    .then (io) =>
      nsp = io.of("/" + @name)
      if io then nsp.emit("update#{@name}Queue",
        queue: @getFullQueue()
        queuelength: @queue.length()
      )
    .catch (error) =>
      @logger.error("Error sending queue to gui: " + error + error.stack)

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
      moduleRouter.get @createModuleRoute("inventory"), (req, res) => # <- define path (will be availbale on /v1/modules/HelloWorld/custom
        res.render(@getTemplatePath("inventory"),
          modulename: @name # <- has to be set for gui functionality
          activeSubmenu: "inventory" # <- has to be set for gui functionality
          mconnenv: req.mconnenv # <- has to be defined for websocket support
        ) # <- render custom.jade template of this module and pass name as var

    @getWebsocketHandler()
    .then (io) =>
      if io
        nsp = io.of("/" + @name)
        nsp.on("connection", (socket) =>
          @updatePresetsOnGui(socket)
          @updateInventoryOnGui(socket)
        )
    .catch (error) =>
      @logger.error error + error.stack
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
    , 1000

    @options = options
    @timeout = if @timeout then @timeout
    else
      @logger.warn("No timeout defined for module \"#{@name}\", set to default value 5000ms")
      @timeout = 5000
    ZookeeperHandler = Module.getZookeeperHandler()
    #generate required zookeeper paths, if they don't yet exist
    ZookeeperHandler.createPathIfNotExist("modules")
    .then => ZookeeperHandler.createPathIfNotExist("modules/" + @name)
    .then => ZookeeperHandler.createPathIfNotExist("modules/" + @name + "/presets") # all presets for marathon apps are stored here (filled by the ModulePreset)
    .then => ZookeeperHandler.createPathIfNotExist("modules/" + @name + "/queue") # all tasks of the queue are registered here and removed if all modules are finished
    .then => ZookeeperHandler.createPathIfNotExist("modules/" + @name + "/inventory") # stores all states of the module like inventory or something else
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
  addToZKInventory: (path, customData, taskData) ->
    fullPath = "modules/" + @name + "/inventory/" + path
    taskData.timestamp = new Date().getTime()
    dataToStore =
      customData: customData
      taskData: taskData.getData()
    logger.debug("INFO", "Create inventory \"" + JSON.stringify(dataToStore) + "\" on node \"#{fullPath}\"")
    ZookeeperHandler = Module.getZookeeperHandler()
    return ZookeeperHandler.createNode(fullPath, JSON.stringify(dataToStore))

  removeFromZKInventory: (path) ->
    fullPath = "modules/" + @name + "/inventory/" + path
    zookeeperHandler = Module.getZookeeperHandler()
    return zookeeperHandler.remove(fullPath)

  # add a task to the queue
  #
  # @param [TaskData] object, that holds all information about the incoming task from marathon
  # @param [callback] method to be called when everything is finished, callback MUST BE
  # CALLED ALLWAYS, since the main task waits for it as the signal, that the module has finished work
  #
  addTask: (taskData, callback) ->
    taskData.state = "idle"
    @logger.info("Task \"#{taskData.getData().taskId}_#{taskData.getData().taskStatus}\" created on queue")
    Module.getZookeeperHandler().exists("modules/#{@name}/queue/" + taskData.getData().taskId + "_" + taskData.getData().taskStatus)
    .then (exists) =>
      unless exists #do not create zookeeper node for cleanup tasks
        if taskData.cleanup then promise = Q.resolve()
        else
          promise = Module.getZookeeperHandler().createNode("modules/#{@name}/queue/" + taskData.getData().taskId + "_" + taskData.getData().taskStatus,
            new Buffer(JSON.stringify({state: "new"})),
            zookeeper.ACL.OPEN, zookeeper.CreateMode.PERSISTENT)
      else
        promise = Q.resolve()
      return promise
    .then =>
      # add task in front of queue if it is a cleanup task
      if taskData.cleanup then @queue.unshift(taskData, callback) else @queue.push(taskData, callback)
    .catch (error) =>
      logger.error("Could not add task to module's queue \"" + error.toString() + "\"", "Module.#{@name}")

  # pause the queue to do sync or anything else, the active task will be processed till end, but no new task will be processed
  # until resume is not called
  #
  pause: ->
    logger.info("Pausing the task queue and waiting for empty worker", "Module.#{@name}.Pause")
    deferred = Q.defer()
    pauseSuccess = false
    # if no active task or task has been finished ->
    if @checkTaskHasFinishedState(@activeTask)
      logger.info("worker has finished work, pausing", "Module.#{@name}.Pause")
      deferred.resolve()
      @queue.pause()
      pauseSuccess = true
    # check in loop if active task has been finished
    else
      intv = setInterval =>
        if @checkTaskHasFinishedState(@activeTask)
          logger.info("worker has finished work, pausing", "Module.#{@name}.Pause")
          clearInterval(intv)
          pauseSuccess = true
          @queue.pause()
          deferred.resolve()
        else
          logger.info("worker is active, wait #{@checkIntervalPauseQueue} to pause queue", "Module.#{@name}.Pause")
      , @checkIntervalPauseQueue
      Q.delay(@timeout).then =>
        unless pauseSuccess
          logger.error("pausing failed because of module-defined timeout #{@timeout}ms", "")
          clearInterval intv
          deferred.reject("pausing failed")
    deferred.promise

  # resumes the queue
  #
  resume: ->
    logger.info("Resuming queue", "Module.#{@name}.Queue")
    @queue.resume()

  startTaskTimeout: (taskData, callback) ->
    Q.delay(@timeout)
    .then =>
      unless @checkTaskHasFinishedState(taskData)
        @failed(taskData, callback, "timeout on task")

  checkTaskIsDone: (taskData) ->
    deferred = Q.defer()
    taskData.start = new Date().getTime()
    taskData.state = "started"
    @activeTask = taskData
    if taskData.cleanup # there is no zookeepernode for cleanup tasks
      deferred.resolve(false)
    else
      Module.getZookeeperHandler().getData("modules/#{@name}/queue/" + taskData.getData().taskId + "_" + taskData.getData().taskStatus)
      .then (tData) =>
        if @checkTaskHasFinishedState(tData)
          allreadyDoneState = tData.state
        else
          allreadyDoneState = false
        deferred.resolve(allreadyDoneState)
      .catch (error) =>
        @logger.error error, error.stack
    deferred.promise

  # main method to work with every element of the queue, main logic of the modules lies here
  # - must be wrongwritten in child instances but must also call the super method
  # - checks, if the task has already been finished by this module
  # @example super(taskData,callback).then -> MODULES STUFF
  #
  worker: (taskData, callback) ->
    @logger.info("Starting worker for task \"" + taskData.getData().taskId + "_" + taskData.getData().taskStatus + "\"")
    require("./QueueManager").WS_SendAllTasks()
    deferred = Q.defer()
    @startTaskTimeout(taskData, callback)
    @checkTaskIsDone(taskData)
    .then (taskIsDone) =>
      if (taskIsDone)
        @allreadyDone(taskData, callback)
      else
        Module.loadPresetForModule(taskData.getData().appId, @name)
        .then (modulePreset) =>
          unless modulePreset
            @noPreset(taskData, callback, "Preset could not be found for app \"#{taskData.getData().appId}\"")
          else unless modulePreset.status is "enabled"
            @noPreset(taskData, callback, "Preset is not enabled for app \"#{taskData.getData().appId}\"")
          else
            @doWork(taskData, modulePreset, callback)
        .catch (error) =>
          @logger.error("Error starting worker for \"#{@name}\" Module: " + error.toString(), error.stack)
          @failed(taskData, callback)
    .catch (error) =>
      @logger.error(error, error.stack)
    deferred.promise

  doWork: (taskData, modulePreset, callback) ->
    @logger.debug("INFO", "Processing task")
    taskStatus = taskData.getData().taskStatus
    if (typeof @["on_#{taskStatus}"] is 'function')
      @["on_#{taskStatus}"].apply(this, [taskData, modulePreset, callback])
    else
      @logger.warn("Unknown status \"#{taskStatus}\" no method defined called 'on_#{taskStatus}'")
      @on_UNDEFINED_STATUS(taskData, modulePreset, callback)

  checkTaskHasFinishedState: (taskData) ->
    finishedStates = [
      "finished"
      "failed"
      "nopreset"
    ]
    unless taskData?.state? then return true
    for state in finishedStates
      if taskData.state is state then return true
    return false # task is not finished

  # finish task
  #
  # @param [String] state
  # @param [TaskData] taskData
  # @param [Function] callback worker callback
  # @param [String] reason optional reason if task has failed
  #
  finishTask: (state, taskData, callback, reason = false) ->
    unless @checkTaskHasFinishedState(taskData) #prevent from recalling if state is already finished
      @logger.debug("INFO", "Set task \"#{taskData.getData().taskId}_#{taskData.getData().taskStatus}\" to state \"#{state}\"" + " #{reason}")
      taskData.state = state
      taskData.stop = new Date().getTime()
      if taskData.cleanup
        callback() # do nothing
        # @activeTask = null
      else
        Module.getZookeeperHandler().setData("modules/#{@name}/queue/" + taskData.getData().taskId + "_" + taskData.getData().taskStatus, {state: state})
        .then =>
          message = "Task \"#{taskData.getData().taskId}_#{taskData.getData().taskStatus}\" state changed to \"#{state}\"! Task Queue is now \"" + @queue.length() + "\""
          if reason then message += " Reason: #{reason}"
          logger.info message, "Module.#{@name}"
        .catch (error) =>
          logger.error("Could not change the task-state of \"#{taskData.getData().taskId}_#{taskData.getData().taskStatus}\" to \"#{state}\"",
            "Module.#{@name} \"" + error.toString() + "\"", error.stack)
        .finally ->
          require("./QueueManager").WS_SendAllTasks()
          callback()

  # method to be called, if a module has successfully finished work
  # <strong> this module has to be called manually from child class </strong>
  #
  # @param [TaskData] object, that holds all information about the incoming taskData from marathon
  # @param [callback] method to be called when everything is finished
  #
  success: (taskData, callback ) ->
    @finishTask("finished", taskData, callback)

  # method to be called, if a module has failed finishing work
  # <strong> this module has to be called manually from child class </strong>
  #
  # @param [TaskData] object, that holds all information about the incoming taskData from marathon
  # @param [callback] method to be called when everything is finished
  #
  failed: (taskData, callback, reason = "") ->
    @finishTask("failed", taskData, callback, reason)

  # method to be called, if a module has failed finishing work
  # <strong> this module has to be called manually from child class </strong>
  #
  # @param [TaskData] object, that holds all information about the incoming taskData from marathon
  # @param [callback] method to be called when everything is finished
  #
  noPreset: (taskData, callback, reason = "") ->
    @finishTask("nopreset", taskData, callback, reason)

  # method to be called, if a module has failed finishing work
  # <strong> this module has to be called manually from child class </strong>
  #
  # @param [TaskData] object, that holds all information about the incoming taskData from marathon
  # @param [callback] method to be called when everything is finished
  #
  undefinedStatus: (taskData, callback, reason = "") ->
    @finishTask("undefinedStatus", taskData, callback, reason)

  # method to be called, if a module has allready done
  # <strong> this module has to be called manually from child class </strong>
  #
  # @param [TaskData] object, that holds all information about the incoming taskData from marathon
  # @param [callback] method to be called when everything is finished
  #
  allreadyDone: (taskData, callback) ->
    unless @checkTaskHasFinishedState(taskData) # prevent from recalling if state is already finished
      @logger.info("Setting task \"#{taskData.getData().taskId}_#{taskData.getData().taskStatus}\" to state \"finished\"")
      taskData.state = "finished"
      taskData.stop = new Date().getTime()
      logger.warn("Task allready done, skipping in queue! Queue is now \"" + @queue.length() + "\"", "Module.#{@name}")
      require("./QueueManager").WS_SendAllTasks()
      # @activeTask = null
      callback()

  #
  # STATICS FOR ALL MODULES
  #

  @allModulesLoadedDeferred: Q.defer()

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
    deferred = Q.defer()
    if process.env.MCONN_MODULE_PREPARE is "true"
      path = require("path")
      exec = require('child_process').exec
      exec("coffee -o " + path.join(process.env.MCONN_MODULE_PATH , folder, "bin") + " -c " + path.join(process.env.MCONN_MODULE_PATH , folder, "src"), (error, stdout, stderr) ->
        if error
          logger.error("Error compiling coffee for module \"#{modulename}\", " + error + "\"", error.stack)
        else
          logger.info("Successfully compiled coffee for module \"#{modulename}\"")
        deferred.resolve()
      )
    else
      logger.debug("INFO", "Skipping Coffeescript Compile for module \"#{modulename}\"")
      deferred.resolve()
    deferred.promise

  @appendModuleJavascripts: (modulename, folder) ->
    path = require("path")
    javascriptsFolder = path.join(process.env.MCONN_MODULE_PATH, folder, "bin", "templates", "public")
    logger.debug("Info", "Appending javascript of module to UI, using folder \"#{javascriptsFolder}\"")
    config = require("../webserver/config/config")
    files = fs.readdirSync(javascriptsFolder)
    for f in files
      parts = f.split(".")
      if parts.length > 1 and parts[parts.length - 1] is "js"
        config.extraJavascriptFiles.push(modulename + "/" + f)

  @appendModuleStyles: (modulename, folder) ->
    path = require("path")
    stylesFolder = path.join(process.env.MCONN_MODULE_PATH, folder, "bin", "templates", "public", "css")
    logger.debug("Info", "Appending css of module to UI, using folder \"#{stylesFolder}\"")
    config = require("../webserver/config/config")
    files = fs.readdirSync(stylesFolder)
    for f in files
      parts = f.split(".")
      if parts.length > 1 and parts[parts.length - 1] is "css"
        config.extraStyles.push(modulename + "/css/" + f)

  # installs node modules from npm package.json dependencies for a module
  #
  # @param [String] modulename
  #
  @installNodeModules: (modulename, folder) ->
    deferred = Q.defer()
    path = require("path")
    exec = require('child_process').exec
    exec("cd " + path.join(process.env.MCONN_MODULE_PATH , folder) + " && npm install --production", (error, stdout, stderr) ->
      if error
        logger.error("Error installing dependencies for module \"#{modulename}\", \"" + error + "\"", error.stack)
      else
        logger.info("Successfully installed dependencies for module \"#{modulename}\"")
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
        logger.debug("INFO", "Found \"" + folder + "\"")
        found = false
        for module in modulesToLoad
          do (module, folder) ->
            if module is folder
              found = true
              if (fs.existsSync(process.env.MCONN_MODULE_PATH + "/#{folder}/package.json"))
                pjson = fs.readFileSync(process.env.MCONN_MODULE_PATH + "/#{folder}/package.json")
                moduleNameInPackageJson = JSON.parse(pjson).name
                logger.debug("INFO", "Modulename from package.json of folder \"#{folder}\" is \"#{moduleNameInPackageJson}\"")
                logger.debug("INFO", "Initiating \"" + moduleNameInPackageJson + "\" from folder \"#{path.join(process.env.MCONN_MODULE_PATH, folder)}\"")
                Module.installNodeModules(moduleNameInPackageJson, folder)
                .then ->
                  Module.compileCoffeescript(moduleNameInPackageJson, folder)
                .then ->
                  Module.appendModuleJavascripts(moduleNameInPackageJson, folder)
                  Module.appendModuleStyles(moduleNameInPackageJson, folder)
                  # add statics to load css/js file in frontend
                  expressStatics[moduleNameInPackageJson] = path.join(process.env.MCONN_MODULE_PATH, folder, "bin", "templates", "public")
                  Module = require(path.join(process.env.MCONN_MODULE_PATH, folder))
                  config = require(path.join(process.env.MCONN_MODULE_PATH, folder + "/config.json"))
                  unless config?
                    logger.error("Error reading config for \"#{module}\", path \"" + path.join(process.env.MCONN_MODULE_PATH, folder + "/config.json\""), "")
                    done()
                  else
                    logger.debug("INFO", "trying to init module #{moduleNameInPackageJson}")
                    modules[moduleNameInPackageJson] = new Module()
                    modules[moduleNameInPackageJson].init(config, moduleRouter, folder)
                    .then ->
                      logger.info("Module \"" + moduleNameInPackageJson + "\" successfully initiated from folder \"#{folder}\"")
                    .catch (error) ->
                      logger.error("Module \"" + moduleNameInPackageJson + "\" could not be initiated \"" + error + "\"", error.stack)
                    .finally ->
                      done()
                .catch (error) ->
                  logger.error error, error.stack
                  done()
              else
                logger.error("\"package.json\" is missing in folder \"#{folder}\" module could not be detected", "")
                done()
        unless found
          logger.debug("INFO", "Folder \"" + folder + "\" is present, but is no module or not activated by environment variable \"MCONN_MODULE_START\"")
          done()
      , =>
        @modules = modules
        logger.debug("INFO", "All modules loaded")
        deferred.resolve(modules)
      )
    catch error
      logger.error error, error.stack
      deferred.resolve()
    deferred.promise
    .then =>
      @allModulesLoadedDeferred.resolve()
    .catch (error) =>
      @logger.error error, error.stack
    deferred.promise

  # load the preset from zookeeper for this application
  #
  @loadPresetForModule: (appid, moduleName) ->
    clearedAppId = appid.split("/")[1]
    logger.debug("INFO", "\"" + moduleName + "\" is loading preset for appId \"#{clearedAppId}\"")
    deferred = Q.defer()
    Module.getZookeeperHandler().exists("modules/" + moduleName + "/presets/" + clearedAppId)
    .then (exists) =>
      if (exists)
        this.getZookeeperHandler().getData("modules/" + moduleName + "/presets/" + clearedAppId)
        .then (config) ->
          deferred.resolve(config)
        .catch (error) ->
          logger.error "Error fetching app for \"" + clearedAppId + "\" for module \"" + moduleName + "\" \"" +  error + "\"", error.stack
          deferred.resolve(false)
      else
        logger.debug "WARN", "Could not find preset for app \"" + clearedAppId + "\" for module \"" + moduleName + "\""
        deferred.resolve(false)
    .catch (error) ->
      logger.error "Error occured loading preset for app \"" + clearedAppId + "\" for module \"" + moduleName + "\" \"" +  error + "\"", error.stack
      deferred.resolve(false)
    return deferred.promise

  @getZookeeperHandler: ->
    require("./ZookeeperHandler")

module.exports = Module
