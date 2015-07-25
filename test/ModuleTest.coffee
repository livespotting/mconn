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

bodyParser = require('body-parser')
chai = require("chai")
sinon = require 'sinon'
sinonChai = require 'sinon-chai'
chai.use sinonChai
expect = chai.expect
express = require("express")
http = require('http')
Q = require("q")
request = require("request")

Module = require("../src/application/classes/Module")
Manager = require("./utils/ProcessManager")

createMarathonRequestdata = require("./utils/Helper").createMarathonRequestdata
createPresetRequestdata = require("./utils/Helper").createPresetRequestdata
webserverIsStarted = require("./utils/Helper").webserverIsStarted
webserverIsKilled = require("./utils/Helper").webserverIsKilled

isEmpty = (obj) ->
  for k of obj
    if obj.hasOwnProperty(k)
      return false
  true
check = (done, f) ->
  try
    f()
    done()
  catch e
    done(e)

environment = (processName, port) ->
  name: processName
  MCONN_HOST: "127.0.0.1"
  MCONN_PORT: port
  MCONN_CREDENTIALS: ""
  MCONN_MODULE_PATH: if process.env.MCONN_TEST_MODULE_PATH then process.env.MCONN_TEST_MODULE_PATH else __dirname + "/testmodules"
  MCONN_MODULE_START: process.env.MCONN_TEST_MODULE_START
  MCONN_MODULE_TEST_DELAY: 250
  MCONN_ZK_HOSTS: if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" else "127.0.0.1:2181"
  MCONN_ZK_PATH: "/mconn-dev-module"
  MCONN_ZK_SESSION_TIMEOUT: 1000

mconn1 = null

# set env defaults
process.env.MCONN_TEST_MODULE_START = if process.env.MCONN_TEST_MODULE_START then process.env.MCONN_TEST_MODULE_START else "Test"

describe "Module Tests", ->
  describe "Unittests", ->
    describe "pause", ->
      it "should wait for activeTask if activeTask has not been finished", (done)->
        async = require("async")
        anyModule = new Module("AnyModule")
        anyModule.checkIntervalPauseQueue = 400
        anyModule.timeout = 1000
        stubCheckTaskHasFinishedState = sinon.stub(anyModule, "checkTaskHasFinishedState")
        stubCheckTaskHasFinishedState.returns(false)
        stubPause = sinon.stub(anyModule.queue, "pause")
        anyModule.pause()
        Q.delay(1000).then ->
          check done, ->
            expect(stubCheckTaskHasFinishedState.callCount).to.be.at.least(2)
            expect(stubPause).not.to.have.been.called
            stubPause.restore()
      it "should pause if activeTask has been finished", (done)->
        async = require("async")
        anyModule = new Module("AnyModule")
        anyModule.checkIntervalPauseQueue = 400
        anyModule.timeout = 1000
        stubCheckTaskHasFinishedState = sinon.stub(anyModule, "checkTaskHasFinishedState")
        stubCheckTaskHasFinishedState.returns(true)
        stubPause = sinon.stub(anyModule.queue, "pause")
        anyModule.pause()
        Q.delay(1000).then ->
          check done, ->
            expect(stubCheckTaskHasFinishedState.callCount).equal(1)
            expect(stubPause).to.have.been.called
            stubPause.restore()
      it "should pause if activeTask has not been finished, but gets finished after a while", (done)->
        async = require("async")
        anyModule = new Module("AnyModule")
        anyModule.checkIntervalPauseQueue = 200
        anyModule.timeout = 1500
        stubCheckTaskHasFinishedState = sinon.stub(anyModule, "checkTaskHasFinishedState")
        stubCheckTaskHasFinishedState.returns(false)
        stubPause = sinon.stub(anyModule.queue, "pause")
        anyModule.pause()
        Q.delay(500)
        .then ->
          expect(stubPause).not.to.have.been.called
          stubCheckTaskHasFinishedState.returns(true) #task has noew been finished
        .delay(500).then ->
          check done, ->
            expect(stubPause).to.have.been.called
            stubPause.restore()
      it "should clear checkIntervl if task has been finished and queue has been paused", (done)->
        async = require("async")
        anyModule = new Module("AnyModule")
        anyModule.checkIntervalPauseQueue = 300
        anyModule.timeout = 1500
        stubCheckTaskHasFinishedState = sinon.stub(anyModule, "checkTaskHasFinishedState")
        stubCheckTaskHasFinishedState.returns(true)
        anyModule.pause()
        Q.delay(1000).then ->
          check done, ->
            expect(stubCheckTaskHasFinishedState.callCount).equal(1)
      it "should clear checkIntervl if timeout has been reached", (done)->
        async = require("async")
        anyModule = new Module("AnyModule")
        anyModule.checkIntervalPauseQueue = 200
        anyModule.timeout = 1000
        stubCheckTaskHasFinishedState = sinon.stub(anyModule, "checkTaskHasFinishedState")
        stubCheckTaskHasFinishedState.returns(false)
        anyModule.pause()
        Q.delay(1500).then ->
          check done, ->
            expect(stubCheckTaskHasFinishedState.callCount).to.be.at.most(5)

  describe "Integrationtests", ->
    before (done) ->
      this.timeout(60000)
      mconn1 = new Manager "bin/start.js", environment("MCONN_NODE_1", 1240)
      webserverIsStarted(1240)
      .then ->
        done()

    describe "check if the #{process.env.MCONN_TEST_MODULE_START}Module has been loaded", ->
      describe "GET /v1/module/list", ->
        this.timeout(5000)
        it "should return array of loaded modules including #{process.env.MCONN_TEST_MODULE_START}", (done) ->
          request.get "http://127.0.0.1:1240/v1/module/list", {json: true}, (error, req, body) ->
            check done, ->
              expect(body[process.env.MCONN_TEST_MODULE_START].name).equal(process.env.MCONN_TEST_MODULE_START)

      describe "GET /v1/module/list/#{process.env.MCONN_TEST_MODULE_START}", ->
        it "should return the data of the #{process.env.MCONN_TEST_MODULE_START}Module", (done) ->
          request.get "http://127.0.0.1:1240/v1/module/list/#{process.env.MCONN_TEST_MODULE_START}", {json: true}, (error, req, body) ->
            check done, ->
              expect(body.name).equal(process.env.MCONN_TEST_MODULE_START)

    describe "Presets API", ->
      describe "CRUD", ->
        describe "- create - ", ->
          it "should respond with count = 1 on POST /v1/module/preset", (done) ->
            request createPresetRequestdata(1240, "/app", process.env.MCONN_TEST_MODULE_START, "enabled"), (error, req, body) ->
              check done, ->
                expect(body.status).equal("ok")
          it "should respond message 'AppId for module #{process.env.MCONN_TEST_MODULE_START} created: /app1'  on POST /v1/module/preset", (done) ->
            request createPresetRequestdata(1240, "/app1", process.env.MCONN_TEST_MODULE_START, "enabled"), (error, req, body) ->
              check done, ->
                expect(body.message).equal("AppId for module #{process.env.MCONN_TEST_MODULE_START} created: /app1")

        describe "- read - ", ->
          it "should respond with Object including preset '/app' for module '#{process.env.MCONN_TEST_MODULE_START}' on GET /v1/module/preset", (done) ->
            request.get "http://127.0.0.1:1240/v1/module/preset", {json: true}, (error, req, body) ->
              check done, ->
                expect(body[process.env.MCONN_TEST_MODULE_START][0].appId).equal('/app')
          it "should respond with Object including preset '/app' on GET /v1/module/preset/#{process.env.MCONN_TEST_MODULE_START}", (done) ->
            request.get "http://127.0.0.1:1240/v1/module/preset/#{process.env.MCONN_TEST_MODULE_START}", {json: true}, (error, req, body) ->
              check done, ->
                expect(body[0].appId).equal('/app')

        describe "- update - ", ->
          it "should respond with status ='ok' on PUT /v1/module/preset", (done) ->
            request createPresetRequestdata(1240, "/app", process.env.MCONN_TEST_MODULE_START, "enabled", "PUT"), (error, req, body) ->
              check done, ->
                expect(body.status).equal("ok")

          it "should respond message 'AppId for module #{process.env.MCONN_TEST_MODULE_START} modified: /app'  on PUT /v1/module/preset", (done) ->
            request createPresetRequestdata(1240, "/app", process.env.MCONN_TEST_MODULE_START, "enabled", "PUT"), (error, req, body) ->
              check done, ->
                expect(body.message).equal("AppId for module #{process.env.MCONN_TEST_MODULE_START} modified: /app")

        # PLEASE NOTE: deletion rely on successfull creations in tests above!
        describe "- delete - ", ->
          it "should respond with 'ok' on DELETE /v1/module/preset", (done) ->
            request createPresetRequestdata(1240, "/app", process.env.MCONN_TEST_MODULE_START, "enabled", "DELETE"), (error, req, body) ->
              check done, ->
                expect(body.status).equal("ok")

          it "should respond with message 'AppId for module Test deleted: /app1' on DELETE v1/module/preset/#{process.env.MCONN_TEST_MODULE_START}", (done) ->
            request createPresetRequestdata(1240, "/app1", process.env.MCONN_TEST_MODULE_START, "enabled", "DELETE"), (error, req, body) ->
              check done, ->
                expect(body.message).equal("AppId for module Test deleted: /app1")

          it "should return empty presetlist on GET v1/module/preset/#{process.env.MCONN_TEST_MODULE_START}", (done) ->
            request.get "http://127.0.0.1:1240/v1/module/preset/#{process.env.MCONN_TEST_MODULE_START}", {json: true}, (error, req, body) ->
              check done, ->
                expect(body.length).equal(0)

      describe "check recovering presets from zookeeper after leader-change (create 3 presets for testing)", ->
        #before: create a preset
        before (done) ->
          this.timeout(60000)
          request createPresetRequestdata(1240, "/app-should-be-loaded-after-restart1", process.env.MCONN_TEST_MODULE_START, "enabled"), (error, req, body) ->
            request createPresetRequestdata(1240, "/app-should-be-loaded-after-restart2", process.env.MCONN_TEST_MODULE_START, "enabled"), (error, req, body) ->
              request createPresetRequestdata(1240, "/app-should-be-loaded-after-restart3", process.env.MCONN_TEST_MODULE_START, "enabled"), (error, req, body) ->
                mconn1.kill()
                Q.delay(5000) # zk session timeout
                .then ->
                  mconn1 = new Manager "bin/start.js", environment("MCONN_NODE_1", 1240)
                  webserverIsStarted(1240)
                  .then ->
                    done()
        it "should recover 3 presets after restart", (done) ->
          request.get "http://127.0.0.1:1240/v1/module/preset/#{process.env.MCONN_TEST_MODULE_START}", {json: true}, (error, req, body) ->
            check done, ->
              expect(body.length).equal(3)
        for i in [1..3]
          do (i) ->
            it "should recover preset '/app-should-be-loaded-after-restart#{i}' after restart", (done) ->
              request.get "http://127.0.0.1:1240/v1/module/preset/#{process.env.MCONN_TEST_MODULE_START}", {json: true}, (error, req, body) ->
                check done, ->
                  found = false
                  for preset in body
                    if preset.appId is "/app-should-be-loaded-after-restart#{i}"
                      found = true
                  expect(found).equal(true)
        after (done) ->
          request createPresetRequestdata(1240, "/app-should-be-loaded-after-restart1", process.env.MCONN_TEST_MODULE_START, "enabled", "DELETE"), (error, req, body) ->
            request createPresetRequestdata(1240, "/app-should-be-loaded-after-restart2", process.env.MCONN_TEST_MODULE_START, "enabled", "DELETE"), (error, req, body) ->
              request createPresetRequestdata(1240, "/app-should-be-loaded-after-restart3", process.env.MCONN_TEST_MODULE_START, "enabled", "DELETE"), (error, req, body) ->
                Q.delay(1500).then ->
                  done()

      describe "check if tasks are only beeing processed if there is an assigned preset", ->
        describe "POST a marathon-task to /v1/queue", ->
          it "should respond with status/message 'ok'",  (done) ->
            request createMarathonRequestdata(1240, "/app-without-a-preset", "task_app_1234"), (error, req, body) ->
              check done, ->
                expect(body.taskId).equal('task_app_1234_TASK_RUNNING')
          it "should return an empty queue after 300ms (working time is 250ms) on GET /v1/queue", (done) ->
            Q.delay(300).then ->
              request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
                check done, ->
                  expect(isEmpty(body)).equal(true, "body is " + JSON.stringify(body))

      describe "preset is disabled", ->
        # add disabled preset
        before (done) ->
          request createPresetRequestdata(1240, "/anotherapp", process.env.MCONN_TEST_MODULE_START, "disabled"), (error, req, body) ->
            done()
        it "should write the status 'disabled' to zk-node", (done) ->
          request.get "http://127.0.0.1:1240/v1/module/preset", {json: true}, (error, req, body) ->
            check done, ->
              expect(body[process.env.MCONN_TEST_MODULE_START][0].status).equal('disabled')
        it "should not process any jobs and quickly remove them from queue (after 300ms, normally they would last 750ms)", (done) ->
          request createMarathonRequestdata(1240, "/anotherapp", "app_1"), (error, req, body) ->
            request createMarathonRequestdata(1240, "/anotherapp", "app2_1"), (error, req, body) ->
              request createMarathonRequestdata(1240, "/anotherapp", "app3_1"), (error, req, body) ->
                Q.delay(300).then ->
                  request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
                    check done, ->
                      expect(body.length).equal(0)

      describe "preset gets enabled", ->
        before (done) ->
          request createPresetRequestdata(1240, "/anotherapp", process.env.MCONN_TEST_MODULE_START, "enabled"), (error, req, body) ->
            done()
        it "should write the status 'enabled' to zk-node", (done) ->
          request.get "http://127.0.0.1:1240/v1/module/preset", {json: true}, (error, req, body) ->
            check done, ->
              expect(body[process.env.MCONN_TEST_MODULE_START][0].status).equal('enabled')
        it "should process jobs now", (done) ->
          request createMarathonRequestdata(1240, "/anotherapp", "app1a_1"), (error, req, body) ->
            request createMarathonRequestdata(1240, "/anotherapp", "app2a_1"), (error, req, body) ->
              request createMarathonRequestdata(1240, "/anotherapp", "app3a_1"), (error, req, body) ->
                Q.delay(300).then ->
                  request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
                    check done, ->
                      expect(body.length).not.equal(0)
        #remove preset to avoid sideeffects on other tests
        after (done) ->
          request createPresetRequestdata(1240, "/anotherapp", process.env.MCONN_TEST_MODULE_START, "enabled", "DELETE"), (error, req, body) ->
            done()

      describe "POST a marathon-task to /v1/queue", ->
        before (done) ->
          request createPresetRequestdata(1240, "/app", process.env.MCONN_TEST_MODULE_START, "enabled"), (error, req, body) ->
            done()
        it "should return taskId 'app_1_TASK_RUNNING'",  (done) ->
          request createMarathonRequestdata(1240, "/app", "app_1"), (error, req, body) ->
            check done, ->
              expect(body.taskId).equal('app_1_TASK_RUNNING')

      describe "GET /v1/queue", ->
        it "should return an empty queue", (done) ->
          Q.delay(1850).then ->
            request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
              check done, ->
                expect(isEmpty(body)).equal(true, "body is " + JSON.stringify(body))

    describe "check processing tasks", ->
      describe "POST one task for preset /app to /v1/queue", ->
        it "should return with taskId 'app_1_TASK_KILLED'", (done) ->
          request createMarathonRequestdata(1240, "/app", "app_1", "TASK_KILLED"), (error, req, body) ->
            check done, ->
              expect(body.taskId).equal('app_1_TASK_KILLED')

      describe "GET /v1/module/queue/list/#{process.env.MCONN_TEST_MODULE_START}", ->
        responseBody = null
        Q.delay(250).then ->
          request createMarathonRequestdata(1240, "/app", "app_2", "TASK_RUNNING"), (error, req, body) ->
            it "should return a queue with 1 task queued", (done) ->
              request.get "http://127.0.0.1:1240/v1/module/queue/list/#{process.env.MCONN_TEST_MODULE_START}", {json: true}, (error, req, body) ->
                responseBody = body
                check done, ->
                  expect(responseBody.length).equal(1)

      describe "GET /v1/queue", ->
        responseBody = null
        Q.delay(250).then ->
          request createMarathonRequestdata(1240, "/app", "app_2", "TASK_KILLED"), (error, req, body) ->
            it "should return a queue with 1 task queued", (done) ->
              request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
                responseBody = body
                check done, ->
                  expect(responseBody.length).equal(1)
                  console.log(body)

        describe "the queued task", ->
          Q.delay(260).then ->
          request createMarathonRequestdata(1240, "/app", "app" + new Date().getTime(), "TASK_RUNNING"), (error, req, body) ->
            it "should have one module registered", ->
              expect(responseBody[0].moduleState.length).equal(1)
            it "should have registered the module '#{process.env.MCONN_TEST_MODULE_START}'",  ->
              expect(responseBody[0].moduleState[0].name).equal(process.env.MCONN_TEST_MODULE_START)
            it "should have the state 'started' for module '#{process.env.MCONN_TEST_MODULE_START}'", ->
              expect(responseBody[0].moduleState[0].state).equal('started')
            it "should be finished after 250ms (that's the static workertime for this test)", (done) ->
              Q.delay(260).then ->
                request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
                  check done, ->
                    expect(isEmpty(body)).equal(true)

      describe "POST multiple (five) tasks", ->
        timeperjob = 250
        before (done) ->
          request createMarathonRequestdata(1240, "/app", "app1_1"), (error, req, body) ->
            request createMarathonRequestdata(1240, "/app", "app2_1"), (error, req, body) ->
              request createMarathonRequestdata(1240, "/app", "app3_1"), (error, req, body) ->
                request createMarathonRequestdata(1240, "/app", "app4_1"), (error, req, body) ->
                  request createMarathonRequestdata(1240, "/app", "app5_1"), (error, req, body) ->
                    done()

        describe "the queue", ->
          responseBody = null
          before (done) ->
            request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
              responseBody = body
              done()
          it "should have tasks queued", ->
            expect(responseBody.length).not.to.equal(0)
          it "should not have 0 tasks after 500ms", (done) ->
            Q.delay(timeperjob + 10).then ->
              request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
                check done, ->
                  expect(body.length).not.to.equal(0)
          it "should have 0 tasks after 1500ms", (done) ->
            this.timeout(3000)
            Q.delay(2000).then ->
              request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
                check done, ->
                  expect(body.length).to.equal(0)

    after (done) ->
      this.timeout(7000)
      request createMarathonRequestdata(1240, "/app", "app1_1", "TASK_KILLED"), (error, req, body) ->
        request createMarathonRequestdata(1240, "/anotherapp", "app1a_1", "TASK_KILLED"), (error, req, body) ->
          request createMarathonRequestdata(1240, "/app", "app2_1", "TASK_KILLED"), (error, req, body) ->
            request createMarathonRequestdata(1240, "/anotherapp", "app2a_1", "TASK_KILLED"), (error, req, body) ->
              request createMarathonRequestdata(1240, "/app", "app3_1", "TASK_KILLED"), (error, req, body) ->
                request createMarathonRequestdata(1240, "/anotherapp", "app3a_1", "TASK_KILLED"), (error, req, body) ->
                  request createMarathonRequestdata(1240, "/app", "app4_1", "TASK_KILLED"), (error, req, body) ->
                    request createMarathonRequestdata(1240, "/anotherapp", "app4a_1", "TASK_KILLED"), (error, req, body) ->
                      request createMarathonRequestdata(1240, "/app", "app5_1", "TASK_KILLED"), (error, req, body) ->
                        Q.delay(5000).then ->
                          mconn1.kill()
                          webserverIsKilled(1240).then ->
                            done()
