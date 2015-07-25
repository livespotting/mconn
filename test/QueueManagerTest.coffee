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
expect = chai.expect
sinon = require 'sinon'
sinonChai = require 'sinon-chai'
chai.use sinonChai
Q = require "q"

QueueManager = require("../src/application/classes/QueueManager")
Module = require("../src/application/classes/Module")
TaskData = require("../src/application/classes/TaskData")

Helper = require("./utils/Helper")

check = (done, f)  ->
  try
    f()
    done()
  catch e
    done(e)

class TestModule extends Module
  constructor: ->
    super("Test")
  # finish task after 500ms
  addTask: (task, done) ->
    Q.delay(500).then ->
      done()

class TestModule2 extends Module
  constructor: ->
    super("Test2")
  # finish task after 500ms
  addTask: (task, done) ->
    Q.delay(500).then ->
      done()

zookeeperMock = Helper.mockZookeeperHandler()

describe "QueueManager", ->
  taskData = null
  before ->
    exampleRequestData =
      body:
        taskId: "ABC"
        taskStatus: "TASK_RUNNING"
        appId: "/dev-app-1"
        host: "testhost"
    taskData = new TaskData(exampleRequestData)
    # prepare testmodule
    testmodule = new TestModule()
    testmodule2 = new TestModule2()
    QueueManager.Module =  ->
      modules: [testmodule, testmodule2]
    QueueManager.zookeeperHandler = ->
      zookeeperMock

  describe "add", ->
    describe "timeout has been reached without resolving all Modulepromises", ->
      it "should call 'timeoutHandler'", (done) ->
        QueueManager.timeoutPerTask = -> 200
        spy = sinon.stub(QueueManager, "timeoutHandler")
        QueueManager.add(taskData)
        Q.delay(1000).then ->
          check done, ->
            QueueManager.timeoutHandler.restore()
            expect(spy).to.have.been.called
      it "should not call 'allModulesFinishedHandler'", (done) ->
        QueueManager.timeoutPerTask = -> 200
        spy = sinon.stub(QueueManager, "allModulesFinishedHandler")
        QueueManager.add(taskData)
        Q.delay(1000).then ->
          check done, ->
            QueueManager.allModulesFinishedHandler.restore()
            expect(spy).not.to.have.been.called
      it "should remove zkNode of each module (called twice)", (done) ->
        QueueManager.timeoutPerTask = -> 200
        spy = sinon.stub(zookeeperMock, "remove", (path) ->
          return Q.resolve()
        )
        QueueManager.add(taskData)
        Q.delay(1000).then ->
          check done, ->
            zookeeperMock.remove.restore()
            expect(spy).to.have.been.calledTwice
      it "should update the GUI with new tasklist (called twice)", (done) ->
        QueueManager.timeoutPerTask = -> 200
        spy = sinon.stub(QueueManager, "WS_SendAllTasks")
        QueueManager.add(taskData)
        Q.delay(1000).then ->
          check done, ->
            QueueManager.WS_SendAllTasks.restore()
            expect(spy).to.have.been.calledTwice

    describe "timeout has been reached but all modules are resolved", ->
      it "should not call 'timeoutHandler'", (done) ->
        QueueManager.timeoutPerTask = -> 600
        spy = sinon.stub(QueueManager, "timeoutHandler")
        QueueManager.add(taskData)
        Q.delay(1000).then ->
          check done, ->
            QueueManager.timeoutHandler.restore()
            expect(spy).not.to.have.been.called
      it "should have called 'allModulesFinishedHandler'", (done) ->
        QueueManager.timeoutPerTask = -> 600
        spy = sinon.stub(QueueManager, "allModulesFinishedHandler")
        QueueManager.add(taskData)
        Q.delay(1000).then ->
          check done, ->
            QueueManager.allModulesFinishedHandler.restore()
            expect(spy).to.have.been.called
      it "should remove zkNode of each module (called twice)", (done) ->
        QueueManager.timeoutPerTask = -> 600
        spy = sinon.stub(zookeeperMock, "remove", (path) ->
          return Q.resolve()
        )
        QueueManager.add(taskData)
        Q.delay(1000).then ->
          check done, ->
            zookeeperMock.remove.restore()
            expect(spy).to.have.been.calledTwice
      it "should update the GUI with new tasklist (called twice)", (done) ->
        QueueManager.timeoutPerTask = -> 600
        spy = sinon.stub(QueueManager, "WS_SendAllTasks")
        QueueManager.add(taskData)
        Q.delay(1000).then ->
          check done, ->
            QueueManager.WS_SendAllTasks.restore()
            expect(spy).to.have.been.calledTwice
