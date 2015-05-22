fs = require("fs")
logger = require("./MConnLogger")("MConnJob")
Q = require("q")

# Holder for all data that comes from marathon request
class MConnJob

  # holds data from marathon
  data: null

  # constructor
  #
  # @param [http.request] req
  # @param [http.response] res
  # @todo res is not neccessary any more
  # @return [MConnJob] this
  #
  constructor: (req, res) ->
    logger.debug("INFO", "Create job")

    @activeModules = new Array()
    if req?.body?
      @data =
        fromMarathon:
          taskId: req.body.taskId
          taskStatus: req.body.taskStatus
          appId: req.body.appId
          host: req.body.host
          ports: req.body.ports
          eventType: req.body.eventType
          timestamp: req.body.timestamp
      logger.debug("INFO", "Processing job \"#{@data.fromMarathon.taskId}_#{@data.fromMarathon.taskStatus}\" to \"MConnJobQueue\"")
    @

  # create a new instance of MConnJob from marathon inventory item
  #
  # @param [Object] item marathon inventory item
  # @return [MConnJob] new instance of MConnJob
  #
  @createFromMarathonInventory: (item)->
    job = new MConnJob
    job.data =
      fromMarathon:
        taskId: item.id
        taskStatus: "TASK_RUNNING"
        appId: item.appId
        host: item.host
        ports: item.ports
        eventType: null
        timestamp: item.startedAt
    return job

  # create a new instance of MconnJob with data
  #
  # @param [Object] data MconnJob-Data
  # @return [MConnJob] new instance of MConnJob
  #
  @load: (data) ->
    job = new MConnJob()
    job.data = data
    return job

  # create a copy of this MConnJob
  #
  # @return [MConnJob] Copy of this MConnJob
  #
  copy: ->
    job = new MConnJob()
    job.data = @data
    return job

module.exports = MConnJob
