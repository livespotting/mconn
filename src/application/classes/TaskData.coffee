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

logger = require("./Logger")("TaskData")

# Holder for all data that comes from marathon request
#
class TaskData

  @logger: logger
  @availableFields: [
    "taskId"
    "taskStatus"
    "appId"
    "host"
    "ports"
    "eventType"
    "timestamp"
  ]

  # fill data of this TaskData instance with passed data
  #
  # @param [Object] data to be filled in this instance
  # @return void
  #
  fillDataFields: (data) ->
    for field in TaskData.availableFields
      if data?[field]? then @[field] = data[field]

  # constructor
  #
  # @param [http.request] req
  # @return [TaskData] this
  #
  constructor: (req) ->
    @activeModules = new Array()
    if req?.body?
      data = req.body
      data = req.body
      @fillDataFields(data)
    @

  # get data of the TaskData instance
  #
  # @return [Object] data of @
  #
  getData: ->
    data = {}
    for field in TaskData.availableFields
      data[field] = @[field]
    data

  # create a new instance of Task from marathon inventory item
  #
  # @param [Object] item marathon inventory item
  # @return [Task] new instance of Task
  #
  @createFromMarathonInventory: (item, cleanupTask) ->
    taskData = new TaskData()
    data = item
    data.taskStatus = "TASK_RUNNING"
    data.taskId = item.id
    data.eventType = null
    data.timestamp = item.statedAt
    taskData.fillDataFields(data)
    if cleanupTask then taskData.cleanup = true
    return taskData

  # create a new instance of TaskData with data
  #
  # @param [Object] data
  # @return [TaskData] new instance of TaskData
  #
  @load: (data, cleanupTask) ->
    taskData = new TaskData()
    taskData.fillDataFields(data)
    if cleanupTask then taskData.cleanup = true
    return taskData

  # create a copy of this TaskData
  #
  # @return [TaskData] Copy of this TaskData
  #
  copy: ->
    taskDataCopy = new TaskData()
    taskDataCopy.fillDataFields(@getData())
    return taskDataCopy

module.exports = TaskData
