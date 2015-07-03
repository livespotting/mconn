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
chai = require 'chai'
spies = require 'chai-spies'
chai.use spies
expect = chai.expect
express = require("express")
http = require('http')
Q = require("q")
request = require("request")

routes = require("../src/application/webserver/routes/index")
MainApp = require("../src/application/App")
Manager = require("./utils/ProcessManager")

process.env.MCONN_TEST_MODULE =  if process.env.MCONN_TEST_MODULE then process.env.MCONN_TEST_MODULE  else "Test"

isEmpty = (obj) ->
  for k of obj
    if obj.hasOwnProperty(k)
      return false
  true
check = ( done, f ) ->
  try
    f()
    done()
  catch e
    done(e)
mconn1 = null

fakeRequestFromMarathon = (taskId, appId, taskStatus = "TASK_RUNNING") ->
  deferred = Q.defer()
  options =
    uri: "http://127.0.0.1:1240/v1/queue"
    method: "POST"
    json:
      taskId: taskId
      taskStatus: taskStatus
      appId: appId
      host: "slave1"
      ports: [1234]
      eventType: "status_update_event"
      timestamp: new Date().getTime()
  request options, (error, req, body) ->
    deferred.resolve(body)
  deferred.promise

createPreset = (appId, moduleName, status, method = "POST") ->
  deferred = Q.defer()
  options =
    uri: "http://127.0.0.1:1240/v1/module/preset"
    method: method
    json:
      appId: appId
      moduleName: moduleName
      status: status
      options:
        actions:
          add: "Moin, Moin"
          remove: "Tschues"
  request options, (error, req, body) ->
    deferred.resolve(body)
  deferred.promise

describe "Module Tests", ->
  before (done) ->
    this.timeout(13000)
    mconn1 = new Manager("bin/start.js",
      name: "MCONN_NODE_1"
      MCONN_HOST: "127.0.0.1"
      MCONN_PORT: 1240
      MCONN_ZK_HOSTS: if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" else "127.0.0.1:2181"
      MCONN_ZK_PATH: "/mconn-dev-module"
      MCONN_MODULE_PATH: if process.env.MCONN_TEST_MODULE_PATH then process.env.MCONN_TEST_MODULE_PATH else  __dirname + "/testmodules"
      MCONN_MODULE_START: process.env.MCONN_TEST_MODULE
      MCONN_MODULE_TEST_DELAY: 250
    )
    Q.delay(10000).then -> done()

  describe "check if the #{process.env.MCONN_TEST_MODULE}Module has been loaded", ->
    describe "GET /v1/module/list", ->
      it "should return array of loaded modules including #{process.env.MCONN_TEST_MODULE}", (done) ->
        request.get "http://127.0.0.1:1240/v1/module/list", {json: true}, (error, req, body) ->
          check done, ->
            expect(body[process.env.MCONN_TEST_MODULE].name).equal(process.env.MCONN_TEST_MODULE)

    describe "GET /v1/module/list/#{process.env.MCONN_TEST_MODULE}", ->
      it "should return the data of the #{process.env.MCONN_TEST_MODULE}Module", (done) ->
        request.get "http://127.0.0.1:1240/v1/module/list/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
          check done, ->
            expect(body.name).equal(process.env.MCONN_TEST_MODULE)

  describe "Presets API", ->
    describe "CRUD", ->
      describe "- create - ", ->
        it "should respond with count = 1 on POST /v1/module/preset", (done) ->
          createPreset("/app", process.env.MCONN_TEST_MODULE, "enabled").then (body) ->
            check done, ->
              expect(body.result.count).equal(1)
        it "should respond with count = 0 on POST /v1/module/preset with unknown module", (done) ->
          createPreset("/app", "Test-not-available", "enabled").then (body) ->
            check done, ->
              expect(body.result.count).equal(0)

      describe "- read - ", ->
        it "should respond with Object including preset '/app' for module '#{process.env.MCONN_TEST_MODULE}' on GET /v1/module/preset", (done) ->
          request.get "http://127.0.0.1:1240/v1/module/preset", {json: true}, (error, req, body) ->
            check done, ->
              expect(body[process.env.MCONN_TEST_MODULE][0].appId).equal('/app')
        it "should respond with Object including preset '/app' on GET /v1/module/preset/#{process.env.MCONN_TEST_MODULE}", (done) ->
          request.get "http://127.0.0.1:1240/v1/module/preset/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
            check done, ->
              expect(body[0].appId).equal('/app')

      describe "- update - ", ->
        it "should respond with count = 1 on PUT /v1/module/preset", (done) ->
          createPreset("/app", process.env.MCONN_TEST_MODULE, "enabled", "PUT").then (body) ->
            check done, ->
              expect(body.result.count).equal(1)

      describe "- delete - ", ->
        it "should respond with 'ok' on DELETE /v1/module/preset", (done) ->
          options =
            uri: "http://127.0.0.1:1240/v1/module/preset"
            method: "DELETE"
            json:
              appId: "/app"
              moduleName: process.env.MCONN_TEST_MODULE
          request options, (error, req, body) ->
            check done, ->
              expect(body.result.errors.length).equal(0)
        it "should return empty presetlist on GET v1/module/preset/#{process.env.MCONN_TEST_MODULE}", (done) ->
          Q.delay(1000).then ->
            request.get "http://127.0.0.1:1240/v1/module/preset/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
              check done, ->
                expect(body.length).equal(0)

    describe "check recovering presets from zookeeper after leader-change (create 3 presets for testing)", ->
      #before: create a preset
      before (done)->
        this.timeout(15000)
        createPreset("/app-should-be-loaded-after-restart1", process.env.MCONN_TEST_MODULE, "enabled").then (body) ->
          createPreset("/app-should-be-loaded-after-restart2", process.env.MCONN_TEST_MODULE, "enabled").then (body) ->
            createPreset("/app-should-be-loaded-after-restart3", process.env.MCONN_TEST_MODULE, "enabled").then (body) ->
              mconn1.kill()
              #wait for automatic restart of node
              mconn1 = new Manager("bin/start.js",
                name: "MCONN_NODE_1"
                MCONN_HOST: "127.0.0.1"
                MCONN_PORT: 1240
                MCONN_ZK_HOSTS: if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" else "127.0.0.1:2181"
                MCONN_ZK_PATH: "/mconn-dev-module"
                MCONN_MODULE_PATH: if process.env.MCONN_TEST_MODULE_PATH then process.env.MCONN_TEST_MODULE_PATH else  __dirname + "/testmodules"
                MCONN_MODULE_START: process.env.MCONN_TEST_MODULE
                MCONN_MODULE_TEST_DELAY: 250
              )
              Q.delay(10000).then -> done()
      it "should recover 3 presets after restart", (done)->
        request.get "http://127.0.0.1:1240/v1/module/preset/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
          check done, ->
            expect(body.length).equal(3)
      for i in [1..3]
        do (i) ->
          it "should recover preset '/app-should-be-loaded-after-restart#{i}' after restart", (done)->
            request.get "http://127.0.0.1:1240/v1/module/preset/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
              check done, ->
                found = false
                for preset in body
                  if preset.appId is "/app-should-be-loaded-after-restart#{i}"
                    found = true
                expect(found).equal(true)
      after (done) ->
        options =
          uri: "http://127.0.0.1:1240/v1/module/preset"
          method: "DELETE"
          json:
            appId: "/app-should-be-loaded-after-restart1"
            moduleName: process.env.MCONN_TEST_MODULE
        request options, ->
          options.json.appId = "/app-should-be-loaded-after-restart2"
          request options, ->
            options.json.appId = "/app-should-be-loaded-after-restart3"
            request options, ->
              Q.delay(1500).then ->
                done()

    describe "check if tasks are only beeing processed if there is an assigned preset", ->
      describe "POST a marathon-task to /v1/queue", ->
        it "should respond with status/message 'ok'",  (done) ->
          fakeRequestFromMarathon("task_app", "/app-without-a-preset").then (body) ->
            check done, ->
              expect(body.status).equal('ok')
        it "should return an empty queue after 100ms (working time is 250ms) on GET /v1/queue", (done) ->
          Q.delay(150).then ->
            request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
              check done, ->
                expect(isEmpty(body)).equal(true, "body is " + JSON.stringify(body))

    describe "preset is disabled", ->
      # add disabled preset
      before (done)->
        createPreset("/anotherapp", process.env.MCONN_TEST_MODULE, "disabled").then (body)->
          done()
      it "should write the status 'disabled' to zk-node", (done) ->
        request.get "http://127.0.0.1:1240/v1/module/preset", {json: true}, (error, req, body) ->
          check done, ->
            expect(body[process.env.MCONN_TEST_MODULE][0].status).equal('disabled')
      it "should not process any jobs and quickly remove them from queue (after 300ms, normally they would last 750ms)", (done) ->
        options = (taskId) ->
          uri: "http://127.0.0.1:1240/v1/queue"
          method: "POST"
          json:
            taskId: taskId
            taskStatus: "TASK_RUNNING"
            appId: "/anotherapp"
            host: "slave1"
            ports: [1234]
            eventType: "status_update_event"
            timestamp: new Date().getTime()
        #add 3 tasks
        request options("app" + new Date().getTime()), (error, req, body) ->
          request options("app2" + new Date().getTime()), (error, req, body) ->
            request options("app3" + new Date().getTime()), (error, req, body) ->
              Q.delay(300).then ->
                request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
                  check done, ->
                    expect(body.length).equal(0)

    describe "preset gets enabled", ->
      before (done)->
        options =
          uri: "http://127.0.0.1:1240/v1/module/preset"
          method: "POST"
          json:
            appId: "/anotherapp"
            moduleName: process.env.MCONN_TEST_MODULE
            status: "enabled"
            options:
              actions:
                add: "Moin, Moin"
                remove: "Tschues"
        request options, (error, req, body) ->
          done()
      it "should write the status 'enabled' to zk-node", (done) ->
        request.get "http://127.0.0.1:1240/v1/module/preset", {json: true}, (error, req, body) ->
          check done, ->
            expect(body[process.env.MCONN_TEST_MODULE][0].status).equal('enabled')
      it "should process jobs now", (done) ->
        options = (taskId) ->
          uri: "http://127.0.0.1:1240/v1/queue"
          method: "POST"
          json:
            taskId: taskId
            taskStatus: "TASK_RUNNING"
            appId: "/anotherapp"
            host: "slave1"
            ports: [1234]
            eventType: "status_update_event"
            timestamp: new Date().getTime()
        #add 3 tasks
        request options("app1a"), (error, req, body) ->
          request options("app2a"), (error, req, body) ->
            request options("app3a"), (error, req, body) ->
              Q.delay(300).then ->
                request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
                  check done, ->
                    expect(body.length).not.equal(0)
      #remove preset to avoid sideeffects on other tests
      after (done) ->
        options =
          uri: "http://127.0.0.1:1240/v1/module/preset"
          method: "DELETE"
          json:
            appId: "/anotherapp"
            moduleName: process.env.MCONN_TEST_MODULE
        request options, (error, req, body) ->
          # wait for all jobs to be completed, then move on to next test
          Q.delay(1000).then ->
            done()

    describe "POST a marathon-task to /v1/queue", ->
      before (done) ->
        options =
          uri: "http://127.0.0.1:1240/v1/module/preset"
          method: "POST"
          json:
            appId: "/app"
            moduleName: process.env.MCONN_TEST_MODULE
            status: "enabled"
            options:
              actions:
                add: "Moin, Moin"
                remove: "Tschues"
        request options, (error, req, body) ->
          done()
      it "should return status/message 'ok'",  (done) ->
        options =
          uri: "http://127.0.0.1:1240/v1/queue"
          method: "POST"
          json:
            taskId: "app"
            taskStatus: "TASK_RUNNING"
            appId: "/app"
            host: "slave1"
            ports: [1234]
            eventType: "status_update_event"
            timestamp: new Date().getTime()
        request options, (error, req, body) ->
          check done, ->
            expect(body.status).equal('ok')

    describe "GET /v1/queue", ->
      it "should return an empty queue", (done) ->
        Q.delay(1850).then ->
          request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
            check done, ->
              expect(isEmpty(body)).equal(true, "body is " + JSON.stringify(body))

  describe "check processing tasks", ->
    describe "POST one task for preset /app to /v1/queue", ->
      it "should return with status/message 'ok'", (done) ->
        options =
          uri: "http://127.0.0.1:1240/v1/queue"
          method: "POST"
          json:
            taskId: "app"
            taskStatus: "TASK_KILLED"
            appId: "/app"
            host: "slave1"
            ports: [1234]
            eventType: "status_update_event"
            timestamp: new Date().getTime()
        request options, (error, req, body) ->
          check done, ->
            expect(body.status).equal('ok')

    describe "GET /v1/module/queue/list/#{process.env.MCONN_TEST_MODULE}", ->
      responseBody = null
      it "should return a queue with 1 task queued",  (done)->
        Q.delay(100).then ->
          request.get "http://127.0.0.1:1240/v1/module/queue/list/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
            responseBody = body
            check done, ->
              expect(responseBody.length).equal(1)

    describe "GET /v1/queue", ->
      responseBody = null
      before (done)->
        request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
          responseBody = body
          done()
      it "should return a queue with 1 task queued",  ->
        expect(responseBody.length).equal(1)

      describe "the queued task", ->
        it "should have one module registered", ->
          expect(responseBody[0].moduleState.length).equal(1)
        it "should have registered the module '#{process.env.MCONN_TEST_MODULE}'",  ->
          expect(responseBody[0].moduleState[0].name).equal(process.env.MCONN_TEST_MODULE)
        it "should have the state 'started' for module '#{process.env.MCONN_TEST_MODULE}'", ->
          expect(responseBody[0].moduleState[0].state).equal('started')
        it "should be finished after 250ms (that's the static workertime for this test)", (done)->
          Q.delay(250).then ->
            request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
              check done, ->
                expect(isEmpty(body)).equal(true)

    describe "POST multiple (five) tasks", ->
      timeperjob = 250
      before (done)->
        options = (taskId) ->
          uri: "http://127.0.0.1:1240/v1/queue"
          method: "POST"
          json:
            taskId: taskId
            taskStatus: "TASK_RUNNING"
            appId: "/app"
            host: "slave1"
            ports: [1234]
            eventType: "status_update_event"
            timestamp: new Date().getTime()
        #add 5 tasks
        request options("app1"), (error, req, body) ->
          request options("app2"), (error, req, body) ->
            request options("app3"), (error, req, body) ->
              request options("app4"), (error, req, body) ->
                request options("app5"), (error, req, body) ->
                  done()

      describe "the queue", ->
        responseBody = null
        before (done)->
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
    this.timeout(6000)
    mconn1.kill()
    Q.delay(5000).then -> done()
