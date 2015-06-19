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

  worker: (taskData, callback) ->
    @logger.info("Starting worker for task " + taskData.getData().taskId + "_" + taskData.getData().taskStatus + " state: " + taskData.state)
    super(taskData, callback )
    .then (allreadyDoneState) =>
      if (allreadyDoneState)
        @allreadyDone(taskData, callback)
      else
        Module.loadPresetForModule(taskData.getData().appId, @name)
        .then (modulePreset) =>
          unless modulePreset
            @noPreset(taskData, callback, "Preset could not be found for app #{taskData.getData().appId}")
          else
            @doWork(taskData, modulePreset, callback)
        .catch (error) =>
          @logger.error("Error starting worker for #{@name} Module: " + error.toString() + ", " + error.stack)
          @failed(taskData, callback)
    .catch (error) =>
      @logger.error error

  doWork: (taskData, modulePreset, callback) ->
    @logger.debug("INFO", "Processing task")
    switch taskData.getData().taskStatus
      when "TASK_RUNNING" then @on_TASK_RUNNING(taskData, modulePreset, callback)
      when "TASK_FAILED" then @on_TASK_FAILED(taskData, modulePreset, callback)
      when "TASK_FINISHED" then @on_TASK_FINISHED(taskData, modulePreset, callback)
      when "TASK_KILLED" then @on_TASK_KILLED(taskData, modulePreset, callback)

  on_TASK_RUNNING: (taskData, modulePreset, callback) ->
    delay = if process.env.MCONN_MODULE_TEST_DELAY? then process.env.MCONN_MODULE_TEST_DELAY else 250
    Q.delay(delay).then =>
      path = taskData.getData().taskId
      customData = "test"
      @addToZKInventory(path, customData, taskData)
      .then =>
        @logger.info(modulePreset.options.actions.add + " " + taskData.getData().taskId)
        @success(taskData, callback)
        @updateInventoryOnGui()
      .catch (error) =>
        @logger.error error

  on_TASK_FAILED: (taskData, modulePreset, callback) ->
    delay = if process.env.MCONN_MODULE_TEST_DELAY? then process.env.MCONN_MODULE_TEST_DELAY else 250
    Q.delay(delay).then =>
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
    deferred.resolve()
    deferred.promise

module.exports = Test
