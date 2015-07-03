#
# @copyright 2015 Livespotting Media GmbH
# @license Apache-2.0
#
# @author Christoph Johannsdotter [c.johannsdotter@livespottingmedia.com]
# @author Jan Stabenow [j.stabenow@livespottingmedia.com]
#

async = require("async")
fs = require("fs")
Q = require("q")
zookeeper = require('node-zookeeper-client')

logger = require("./Logger")("QueueManager")
Module = require("./Module")
TaskData = require("./TaskData")

# Controlls all incoming marathon tasks by adding them to main-queue and module-queue
#
class QueueManager

  # zk handler
  @zookeeperHandler: ->
    return require("./ZookeeperHandler")

  # total time, after a task has to be finished (todo: this is not activated atm)
  @timeoutPerTask: 120000

  # crate an async queue to hold all the states of modules for each task in one main-task
  @queue: async.queue (taskData, callback) =>
    @activeTask = taskData
    @activeTask.start = new Date().getTime()
    @activeTask.state = "Waiting for all modules"
    # wait for all modules to finish work, than finish this task
    Q.allSettled(taskData.modulePromises)
    .then =>
      if @activeTask
        @activeTask.stop = new Date().getTime()
        @activeTask.state = "All modules finished"
    .catch (error) ->
      logger.error(error.toString(), error.stack)
    .finally ->
      callback()

  # add task to queues
  #
  # @param [taskData] taskData taskData to hold the data of the marathon request
  # @param [Boolean] recovery flag to determine if the task has to be recovered after an app restart
  # @todo Refactor this method, since it is way to long
  # @return [Promise]
  #
  @add: (taskData, recovery = false) ->
    logger.debug("INFO", "Task \"#{taskData.getData().taskId}_#{taskData.getData().taskStatus}\" created on queue")
    promises = []

    # if flag is true, do not recreate a node on zookeeper for this task
    if recovery
      promise = Q.resolve()
    else
      # save task on zookeeper
      promise = @zookeeperHandler().createNode("queue/" + taskData.getData().taskId + "_" + taskData.getData().taskStatus,
        new Buffer(JSON.stringify(taskData.getData()))
      , zookeeper.ACL.OPEN, zookeeper.CreateMode.PERSISTENT)
    copiedTaskDataForModules = {}
    promise.then =>
      for name, m of Module.modules
        do (name, m) ->
          # create a new promise for each task of the modules
          deferred = Q.defer()
          promises.push(deferred.promise)
          taskDataCopy = taskData.copy() # to prevent from sideeffects by call-by-reference, generate a taskData copy for each module
          # used to track status changes for the main task
          copiedTaskDataForModules[name] = taskDataCopy

          # add task to module's queue
          m.addTask(taskDataCopy, ->
            logger.debug("INFO","Resolving promise of task " + taskData.getData().taskId + "_" + taskData.getData().taskStatus + " for task #{name}")
            deferred.resolve()
          )
      # add task to main queue
      @queue.push(
        task: taskData
        copiedTaskDataForModules: copiedTaskDataForModules
        modulePromises: promises
      , =>
        # if all modules have finished work,cleanup task on zookeeper
        @zookeeperHandler().remove("queue/" + taskData.getData().taskId + "_" + taskData.getData().taskStatus)
        .then  =>
          logger.debug("INFO", taskData.getData().taskId + " finished, cleaning up")
          for name, m of Module.modules
            do (name) =>
              @zookeeperHandler().remove("modules/#{name}/queue/" + taskData.getData().taskId + "_" + taskData.getData().taskStatus)
              .then ->
                logger.debug("INFO", "Remove finished task \"#{taskData.getData().taskId}_#{taskData.getData().taskStatus}\" from \"#{name}\" queue")
              .catch (error) ->
                logger.error("Could not remove task \"#{taskData.getData().taskId}_#{taskData.getData().taskStatus}\" from \"#{name}\" queue \"" + error.toString() + "\"", error.stack)
              .finally =>
                @WS_SendAllTasks()
          logger.debug("INFO", "Remove finished task \"#{taskData.getData().taskId}_#{taskData.getData().taskStatus}\" from queue. Now \"#{@queue.length()}\" tasks in queue")
        .catch (error) ->
          logger.error("Could not remove task \"#{taskData.getData().taskId}_#{taskData.getData().taskStatus}\" from queue \"" + error.toString + "\"", error.stack)
      )
      @WS_SendAllTasks()
    .catch (error) ->
      logger.error("Could not save task \"{taskData.getData().taskId}_#{taskData.getData().taskStatus}\" on \"modules/#{name}/queue/\", \"" + error.toString() + "\"", error.stack)
      deferred.resolve()

  # send all tasks to gui
  #
  # @param [socket.io socket] socket to push
  # @param [Array] taskDatas array of tasks, processed for webview
  # @return [null]
  #
  @WS_SendAllTasks: (socket, taskDatas = @createTaskDataForWebview()) ->
    app = require("../App").app
    if app? and app.get("io")?
      io = app.get("io")
      modules = require("./Module").modules
      for modulename,module of modules
        io.of("/#{module.name}").emit("allTasks", taskDatas)
      io.of("/home").emit("allTasks", taskDatas)
    return

  # calculate runtime of a task
  #
  # @param [TaskData] taskData
  # @return [Number] runtime of task
  #
  @getRuntime: (taskData) ->
    endingTime = if taskData.stop then taskData.stop else new Date().getTime()
    if taskData.start
      # calc runtime and append zero if no digit after comma
      runtime = Math.round( ((endingTime - taskData.start) / 100))
      unless runtime % 10 then appendZero = true else appendZero = false
      runtime = if appendZero then (runtime / 10) + ".0" else runtime / 10
    else
      runtime = 0
    return runtime

  # process task for a better display ability on ui
  #
  # @param [TaskData] taskData
  # @return [Object] task processed for gui
  #
  @processTaskForWebview: (taskData, copiedTaskDataForModules) ->
    if taskData instanceof TaskData
      task = {}
      task.id = taskData.getData().taskId + "_" + taskData.getData().taskStatus
      task.data = taskData.getData()
      task.cleanup = taskData.cleanup
      task.moduleState = []
      if copiedTaskDataForModules
        for module, copiedTask of copiedTaskDataForModules
          task.moduleState.push
            name: module
            error: copiedTask.error
            state: copiedTask.state
            runtime: @getRuntime(copiedTask)
      task.runtime = @getRuntime(taskData)
      task.state = taskData.state
      return task
    else
      return false

  # create an array of viewable tasks for the UI
  #
  # @return [Array] array of tasks to push to UI
  #
  @createTaskDataForWebview: ->
    tasksData = new Array()
    # activetask
    if @activeTask and @activeTask.state isnt "All modules finished"
      task = @processTaskForWebview(@activeTask.task, @activeTask.copiedTaskDataForModules)
      task.active = true
      tasksData.push(task)
    # queued tasks
    for asyncTask in @queue.tasks
      if task = @processTaskForWebview(asyncTask.data.task, asyncTask.data.copiedTaskDataForModules)
        tasksData.push(task)
    return tasksData

module.exports = QueueManager
