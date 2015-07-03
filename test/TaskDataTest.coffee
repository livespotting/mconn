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

chai = require 'chai'
spies = require 'chai-spies'
chai.use spies
expect = chai.expect

TaskData = require("../src/application/classes/TaskData")

TaskData.availableFields =
  [
    "taskId"
    "taskStatus"
    "appId"
    "host"
  ]
exampleRequestData =
  body:
    taskId: "ABC"
    taskStatus: "TASK_RUNNING"
    appId: "/dev-app-1"
    host: "testhost"

describe "TaskData", ->
  describe "constructor", (done) ->
    it "should fill all TaskData.availableFields with data from request", ->
      taskData = new TaskData(exampleRequestData)
      data = taskData.getData()
      expect(data.taskId).equal("ABC")
      expect(data.taskStatus).equal("TASK_RUNNING")
      expect(data.appId).equal("/dev-app-1")
      expect(data.host).equal("testhost")

  describe "createFromMarathonInventory", ->
    taskData = null
    before ->
      exampleMarathonInventoryItem =
        id: "ABC"
        appId: "/dev-app-1"
        host: "testhost"
      taskData = TaskData.createFromMarathonInventory(exampleMarathonInventoryItem, cleanup = true)
    it "should fill all TaskData.availableFields with data from MarathonInventory", ->
      data = taskData.getData()
      expect(data.taskId).equal("ABC")
      expect(data.taskStatus).equal("TASK_RUNNING")
      expect(data.appId).equal("/dev-app-1")
      expect(data.host).equal("testhost")
    it "should set the flag 'cleanup' to true", ->
      expect(taskData.cleanup).equal(true)

  describe "copy", ->
    it "should create a copy of TaskData instance instead of a reference", ->
      taskData = new TaskData(exampleRequestData)
      taskDataCopy = taskData.copy()
      taskData.taskId = "abc"
      taskDataCopy.taskId = "ABCDE"
      # test that no reference has been copied but the whole object
      expect(taskData.taskId).equal("abc")
      expect(taskDataCopy.taskId).equal("ABCDE")

  describe "load", ->
    taskData = null
    before ->
      data =
        taskId: "ABC"
        taskStatus: "TASK_RUNNING"
        appId: "/dev-app-1"
        host: "testhost"
      taskData = TaskData.load(data, cleanup = true)
    it "should fill all TaskData.availableFields with data from passed data", ->
      data = taskData.getData()
      expect(data.taskId).equal("ABC")
      expect(data.taskStatus).equal("TASK_RUNNING")
      expect(data.appId).equal("/dev-app-1")
      expect(data.host).equal("testhost")
    it "should set the flag 'cleanup' to true", ->
      expect(taskData.cleanup).equal(true)

  describe "getData", ->
    it "should return all fields of taskData", ->
      taskData = new TaskData(exampleRequestData)
      data = taskData.getData()
      expect(data.taskId).equal("ABC")
      expect(data.taskStatus).equal("TASK_RUNNING")
      expect(data.appId).equal("/dev-app-1")
      expect(data.host).equal("testhost")
    it "should not return fields, that are not set within availableFields" , ->
      taskData = new TaskData(exampleRequestData)
      taskData.anyothervar = "anyother"
      data = taskData.getData()
      expect(data.anyothervar?).equal(false)
