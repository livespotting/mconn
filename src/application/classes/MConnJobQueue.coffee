async = require("async")
fs = require("fs")
logger = require("./MConnLogger")("MConnJobQueue")
Q = require("q")
zookeeper = require('node-zookeeper-client')

MConnModule = require("./MConnModule")

# Controlls all incoming marathon jobs by adding them to main-queue and module-queue
#
class MConnJobQueue

  # array to hold the last 3 jobs to display in gui
  @lastJobs = new Array()

  # zk handler
  @zookeeperHandler: ->
    return require("./MConnZookeeperHandler")

  # total time, after a job has to be finished (todo: this is not activated atm)
  @timeoutPerJob: 120000

  # crate an async queue to hold all the states of modules for each job in one task
  @queue: async.queue (data, callback) =>
    @currentTask = data
    @currentTask.start = new Date().getTime()
    @currentTask.state = "waiting for all modules to complete"
    @lastJobs.push(@currentTask)
    @lastJobs = @lastJobs.slice(-1)
    # wait for all modules to finish work, than finish this job
    Q.allSettled(data.modulePromises)
    .then =>
      if @currentTask
        @currentTask.stop = new Date().getTime()
        @currentTask.state = "all modules finished"
    .catch (error) ->
      console.log(error)
    .finally ->
      callback()

  # add job to queues
  #
  # @param [MConnJob] job job to hold the data of the marathon request
  # @param [Boolean] jobrecovery flag to determine if the job has to be recovered after an app restart
  # @todo Refactor this method, since it is way to long
  # @return [Promise]
  #
  @add: (job, jobrecovery = false) ->
    logger.debug("INFO", "Job \"#{job.data.fromMarathon.taskId}_#{job.data.fromMarathon.taskStatus}\" created on jobqueue")
    promises = []

    # if flag is true, do not recreate a node on zookeeper for this job
    if jobrecovery
      promise = Q.resolve()
    else
      # save job on zookeeper
      promise = @zookeeperHandler().createNode("jobqueue/" + job.data.fromMarathon.taskId + "_" + job.data.fromMarathon.taskStatus,
        new Buffer(JSON.stringify(job.data))
      , zookeeper.ACL.OPEN, zookeeper.CreateMode.PERSISTENT)

    spawnedChildJobs = {}

    promise.then =>
      for name, m of MConnModule.modules
        do (name, m) ->
          # create a new promise for each task of the modules
          deferred = Q.defer()
          promises.push(deferred.promise)
          jobChild = job.copy() # to prevent from sideeffects by call-by-reference, generate a job copy for each module
          # used to track status changes for the main job
          spawnedChildJobs[name] = jobChild

          # add job to module's queue
          m.addJob(jobChild, ->
            logger.debug("INFO","resolving promise of job " + job.data.fromMarathon.taskId + "_" + job.data.fromMarathon.taskStatus + " for job #{name}")
            deferred.resolve()
          )

      # add job to main queue
      @queue.push(
        task: job
        spawnedChildJobs: spawnedChildJobs
        modulePromises: promises
      , =>
        # if all modules have finished work,cleanup job on zookeeper
        @zookeeperHandler().remove("jobqueue/" + job.data.fromMarathon.taskId + "_" + job.data.fromMarathon.taskStatus)
        .then  =>
          logger.debug("INFO", job.data.fromMarathon.taskId + " finished, cleaning up")
          @currentTask = null
          for name, m of MConnModule.modules
            do (name) =>
              @zookeeperHandler().remove("modules/#{name}/jobqueue/" + job.data.fromMarathon.taskId + "_" + job.data.fromMarathon.taskStatus)
              .then ->
                logger.debug("INFO", "Remove finished job \"#{job.data.fromMarathon.taskId}_#{job.data.fromMarathon.taskStatus}\" from \"#{name}\" jobqueue")
              .catch (error) ->
                logger.logError("Could not remove job \"#{job.data.fromMarathon.taskId}_#{job.data.fromMarathon.taskStatus}\" from \"#{name}\" queue \"" + error.toString() + "\"")
              .finally =>
                @WS_SendAllJobs()
          logger.debug("INFO", "Remove finished job \"#{job.data.fromMarathon.taskId}_#{job.data.fromMarathon.taskStatus}\" from queue. Now \"#{@queue.length()}\" jobs in queue")
        .catch (error) ->
          logger.logError("Could not remove job \"#{job.data.fromMarathon.taskId}_#{job.data.fromMarathon.taskStatus}\" from queue \"" + error.toString + "\"")
      )
      @WS_SendAllJobs()
    .catch (error) ->
      logger.logError("Could not save job \"{job.data.fromMarathon.taskId}_#{job.data.fromMarathon.taskStatus}\" on \"modules/#{name}/jobqueue/\", \"" + error.toString() + "\"")
      deferred.resolve()

  # send all jobs to gui
  #
  # @param [Array] jobsData array of jobs, processed for webview
  # @return [null]
  #
  @WS_SendAllJobs: (jobsData = @createJobDataForWebview()) ->
    app = require("../App").app
    if app? and app.get("io")?
      socket = app.get("io").sockets
      socket.emit("allJobs", jobsData)
    return

  # calculate runtime of a job
  #
  # @param [MConnJob] job
  # @return [Number] runtime of job
  #
  @getRuntime: (job) ->
    endingTime = if job.stop then job.stop else new Date().getTime()
    if job.start
      # calc runtime and append zero if no digit after comma
      runtime = Math.round( ((endingTime - job.start) / 100))
      unless runtime % 10 then appendZero = true else appendZero = false
      runtime = if appendZero then (runtime/10) + ".0" else runtime/10
    else
      runtime = 0
    return runtime

  # process task for a better display ability on ui
  #
  # @param [Async.Task] task
  # @return [Object] job processed for gui
  #
  @processTaskForWebview: (task) ->
    if task
      job = {}
      job.runtime = @getRuntime(task)
      job.taskId = task.task.data.fromMarathon.taskId
      job.appId = task.task.data.fromMarathon.appId
      job.marathonData = task.task.data.fromMarathon
      job.cleanup = task.task.cleanup
      job.state = task.state
      job.states = []
      for module, childjob of task.spawnedChildJobs
        job.states.push
          modulename: module
          error: childjob.error
          state: childjob.state
          runtime: @getRuntime(childjob)
      return job
    else
      return false

  # create an array of viewable tasks for the UI
  #
  # @return [Array] array of jobs to push to UI
  #
  @createJobDataForWebview: ->
    jobsData = new Array()
    # currenttask
    if job = @processTaskForWebview(@currentTask)
      job.current = true
      jobsData.push(job)
    # queued tasks
    for task in @queue.tasks
      if job = @processTaskForWebview(task.data)
        jobsData.push(job)
    return jobsData

module.exports = MConnJobQueue
