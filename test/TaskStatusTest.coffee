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

TestModule = require("./testmodules/Test/src/module.coffee")

describe "Handle taskstatus from marathon", ->
  testmodule = new TestModule()
  it "should call method 'on_$TASK_STATUS' if there is a method 'on_$TASK_STATUS' defined", ->
    spy = sinon.spy()
    testmodule.on_TASK_KILLED = spy
    taskDataMock =
      getData: ->
        return {
          taskStatus: "TASK_KILLED"
        }
    modulePresetMock = {}
    callbackMock = {}
    testmodule.doWork(taskDataMock, modulePresetMock, callbackMock)
    expect(spy).to.have.been.called
  it "should call method 'on_UNDEFINED_STATUS' mehtod for submitted status is not provided by module", ->
    spy = sinon.spy()
    testmodule.on_UNDEFINED_STATUS = spy
    taskDataMock =
      getData: ->
        return {
          taskStatus: "TASK_STATUS_IS_FOO"
        }
    modulePresetMock = {}
    callbackMock = {}
    testmodule.doWork(taskDataMock, modulePresetMock, callbackMock)
    expect(spy).to.have.been.called
