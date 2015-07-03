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

Q = require("q")
Module = require "../../../bin/classes/Module"
class Test extends Module

  timeout: 10000

  constructor: ->
    super("Test")

  init: (options, moduleRouter, folder) ->
    Q = require("q")
    deferred = Q.defer()
    super(options, moduleRouter, folder).then ->
      deferred.resolve()
    deferred.promise

  on_TASK_RUNNING: (taskData, modulePreset, callback) ->
    delay = if process.env.MCONN_MODULE_TEST_DELAY? then process.env.MCONN_MODULE_TEST_DELAY else 250
    Q.delay(delay)
    .then =>
      path = taskData.getData().taskId
      customData = "test"
      return @addToZKInventory(path, customData, taskData)
    .then =>
      @logger.info(modulePreset.options.actions.add + " " + taskData.getData().taskId)
      @success(taskData, callback)
      @updateInventoryOnGui()
    .catch (error) =>
      @failed(taskData, callback, error)

  on_TASK_FAILED: (taskData, modulePreset, callback) ->
    delay = if process.env.MCONN_MODULE_TEST_DELAY? then process.env.MCONN_MODULE_TEST_DELAY else 250
    Q.delay(delay)
    .then =>
      path = taskData.getData().taskId
      @removeFromZKInventory(path)
    .then =>
      @logger.info(modulePreset.options.actions.remove + " " + taskData.getData().taskId)
      @success(taskData, callback)
      @updateInventoryOnGui()
    .catch (error) =>
      @failed(taskData, callback, error)

  on_TASK_KILLED: (taskData, modulePreset, callback) ->
    @on_TASK_FAILED(taskData, modulePreset, callback)

  on_TASK_FINISHED: (taskData, modulePreset, callback) ->
    @on_TASK_FAILED(taskData, modulePreset, callback)

  cleanUpInventory: (result) ->
    @logger.debug("INFO", "Starting inventory cleanup")
    deferred = Q.defer()
    for m in result.missing
      m.taskStatus = "TASK_RUNNING"
      @addTask(m, =>
        @logger.info("Cleanup task " + m.getData().taskId + " successfully added")
      )
    for o in result.wrong
      o.taskStatus = "TASK_KILLED"
      @addTask(o, =>
        @logger.info("Cleanup task " + o.getData().taskId + " successfully removed")
      )
    @logger.info("Cleanup initiated, added " + (result.wrong.length + result.missing.length) + " tasks")
    deferred.resolve()
    deferred.promise

module.exports = Test
