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

logger = require("./Logger")("JobQueue")
Module = require("./Module")

# Controlls all incoming marathon jobs by adding them to main-queue and module-queue
#
class JobQueue

  # array to hold the last 3 jobs to display in gui
  @lastJobs = new Array()

  # zk handler
  @zookeeperHandler: ->
    return require("./ZookeeperHandler")

  # total time, after a job has to be finished (todo: this is not activated atm)
  @timeoutPerJob: 120000

  # crate an async queue to hold all the states of modules for each job in one task
  @queue: async.queue (data, callback) =>
    @currentTask = data
    @currentTask.start = new Date().getTime()
    @currentTask.state = "Waiting for all modules"
    @lastJobs.push(@currentTask)
    @lastJobs = @lastJobs.slice(-1)
    # wait for all modules to finish work, than finish this job
    Q.allSettled(data.modulePromises)
    .then =>
      if @currentTask
        @currentTask.stop = new Date().getTime()
        @currentTask.state = "All modules finished"
    .catch (error) ->
      logger.error(error.toString())
    .finally ->
      callback()

  # add job to queues
  #
  # @param [Job] job job to hold the data of the marathon request
  # @param [Boolean] jobrecovery flag to determine if the job has to be recovered after an app restart
  # @todo Refactor this method, since it is way to long
  # @return [Promise]
  #
  @add: (job, jobrecovery = false) ->
    logger.debug("INFO", "Job \"#{job.data.fromMarathonEvent.taskId}_#{job.data.fromMarathonEvent.taskStatus}\" created on jobqueue")
    promises = []

    # if flag is true, do not recreate a node on zookeeper for this job
    if jobrecovery
      promise = Q.resolve()
    else
      # save job on zookeeper
      promise = @zookeeperHandler().createNode("jobqueue/" + job.data.fromMarathonEvent.taskId + "_" + job.data.fromMarathonEvent.taskStatus,
        new Buffer(JSON.stringify(job.data))
      , zookeeper.ACL.OPEN, zookeeper.CreateMode.PERSISTENT)

    spawnedChildJobs = {}

    promise.then =>
      for name, m of Module.modules
        do (name, m) ->
          # create a new promise for each task of the modules
          deferred = Q.defer()
          promises.push(deferred.promise)
          jobChild = job.copy() # to prevent from sideeffects by call-by-reference, generate a job copy for each module
          # used to track status changes for the main job
          spawnedChildJobs[name] = jobChild

          # add job to module's queue
          m.addJob(jobChild, ->
            logger.debug("INFO","Resolving promise of job " + job.data.fromMarathonEvent.taskId + "_" + job.data.fromMarathonEvent.taskStatus + " for job #{name}")
            deferred.resolve()
          )

      # add job to main queue
      @queue.push(
        task: job
        spawnedChildJobs: spawnedChildJobs
        modulePromises: promises
      , =>
        # if all modules have finished work,cleanup job on zookeeper
        @zookeeperHandler().remove("jobqueue/" + job.data.fromMarathonEvent.taskId + "_" + job.data.fromMarathonEvent.taskStatus)
        .then  =>
          logger.debug("INFO", job.data.fromMarathonEvent.taskId + " finished, cleaning up")

          for name, m of Module.modules
            do (name) =>
              @zookeeperHandler().remove("modules/#{name}/jobqueue/" + job.data.fromMarathonEvent.taskId + "_" + job.data.fromMarathonEvent.taskStatus)
              .then ->
                logger.debug("INFO", "Remove finished job \"#{job.data.fromMarathonEvent.taskId}_#{job.data.fromMarathonEvent.taskStatus}\" from \"#{name}\" jobqueue")
              .catch (error) ->
                logger.error("Could not remove job \"#{job.data.fromMarathonEvent.taskId}_#{job.data.fromMarathonEvent.taskStatus}\" from \"#{name}\" queue \"" + error.toString() + "\"")
              .finally =>
                @WS_SendAllJobs()
          logger.debug("INFO", "Remove finished job \"#{job.data.fromMarathonEvent.taskId}_#{job.data.fromMarathonEvent.taskStatus}\" from queue. Now \"#{@queue.length()}\" jobs in queue")
        .catch (error) ->
          logger.error("Could not remove job \"#{job.data.fromMarathonEvent.taskId}_#{job.data.fromMarathonEvent.taskStatus}\" from queue \"" + error.toString + "\"")
      )
      @WS_SendAllJobs()
    .catch (error) ->
      logger.error("Could not save job \"{job.data.fromMarathonEvent.taskId}_#{job.data.fromMarathonEvent.taskStatus}\" on \"modules/#{name}/jobqueue/\", \"" + error.toString() + "\"")
      deferred.resolve()

  # send all jobs to gui
  #
  # @param [socket.io socket] socket to push
  # @param [Array] jobsData array of jobs, processed for webview
  # @return [null]
  #
  @WS_SendAllJobs: (socket, jobsData = @createJobDataForWebview()) ->
    app = require("../App").app
    if app? and app.get("io")?
      io = app.get("io")
      modules = require("./Module").modules
      for modulename,module of modules
        io.of("/#{module.name}").emit("allJobs", jobsData)
      io.of("/home").emit("allJobs", jobsData)
    return

  # calculate runtime of a job
  #
  # @param [Job] job
  # @return [Number] runtime of job
  #
  @getRuntime: (job) ->
    endingTime = if job.stop then job.stop else new Date().getTime()
    if job.start
      # calc runtime and append zero if no digit after comma
      runtime = Math.round( ((endingTime - job.start) / 100))
      unless runtime % 10 then appendZero = true else appendZero = false
      runtime = if appendZero then (runtime / 10) + ".0" else runtime / 10
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
      job.id = task.task.data.fromMarathonEvent.taskId + "_" + task.task.data.fromMarathonEvent.taskStatus
      job.marathonData = task.task.data.fromMarathonEvent
      job.cleanup = task.task.cleanup
      job.moduleState = []
      for module, childjob of task.spawnedChildJobs
        job.moduleState.push
          name: module
          error: childjob.error
          state: childjob.state
          runtime: @getRuntime(childjob)
      job.runtime = @getRuntime(task)
      job.state = task.state
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
    if @currentTask and @currentTask.state isnt "All modules finished" and job = @processTaskForWebview(@currentTask)
      job.current = true
      jobsData.push(job)
    # queued tasks
    for task in @queue.tasks
      if job = @processTaskForWebview(task.data)
        jobsData.push(job)
    return jobsData

module.exports = JobQueue
