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

fs = require("fs")
Q = require("q")

logger = require("./Logger")("Job")

# Holder for all data that comes from marathon request
# @todo: RENAME CLASS TO EventData
class Job

  # holds data from marathon
  data: null

  # constructor
  #
  # @param [http.request] req
  # @param [http.response] res
  # @todo res is not neccessary any more
  # @return [Job] this
  #
  constructor: (req, res) ->
    @activeModules = new Array()
    if req?.body?
      @data =
        fromMarathonEvent:
          taskId: req.body.taskId
          taskStatus: req.body.taskStatus
          appId: req.body.appId
          host: req.body.host
          ports: req.body.ports
          eventType: req.body.eventType
          timestamp: req.body.timestamp
      logger.debug("INFO", "Processing job \"#{@data.fromMarathonEvent.taskId}_#{@data.fromMarathonEvent.taskStatus}\" to \"JobQueue\"")
    @

  # create a new instance of Job from marathon inventory item
  #
  # @param [Object] item marathon inventory item
  # @return [Job] new instance of Job
  #
  @createFromMarathonInventory: (item, cleanupTask) ->
    job = new Job
    job.data =
      fromMarathonEvent:
        taskId: item.id
        taskStatus: "TASK_RUNNING"
        appId: item.appId
        host: item.host
        ports: item.ports
        eventType: null
        timestamp: item.startedAt
    if cleanupTask then job.cleanup = true
    return job

  # create a new instance of MconnJob with data
  #
  # @param [Object] data MconnJob-Data
  # @return [Job] new instance of Job
  #
  @load: (data, cleanupTask) ->
    job = new Job()
    job.data = data
    if cleanupTask then job.cleanup = true
    return job

  # create a copy of this Job
  #
  # @return [Job] Copy of this Job
  #
  copy: ->
    job = new Job()
    job.data = @data
    return job

module.exports = Job
