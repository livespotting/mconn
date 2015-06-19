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

describe "Module Tests", ->
  before (done) ->
    this.timeout(13000)
    mconn1 = new Manager("bin/start.js",
      name: "MCONN_NODE_1"
      MCONN_HOST: "127.0.0.1"
      MCONN_PORT: 1240
      MCONN_ZK_HOSTS: if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" else "127.0.0.1:2181"
      MCONN_ZK_PATH: "/mconn-dev-module"
      MCONN_MODULE_PATH: __dirname + "/testmodules"
      MCONN_MODULE_START: "Test"
      MCONN_MODULE_TEST_DELAY: 250
    )
    Q.delay(10000).then -> done()

  describe "check if the TestModule is loaded", ->
    describe "GET /v1/module/list", ->
      it "should be Test", (done) ->
        request.get "http://127.0.0.1:1240/v1/module/list", {json: true}, (error, req, body) ->
          check done, ->
            expect(body.Test.name).equal('Test')

    describe "GET /v1/module/list/TestModule", ->
      it "should be Test", (done) ->
        request.get "http://127.0.0.1:1240/v1/module/list/Test", {json: true}, (error, req, body) ->
          check done, ->
            expect(body.name).equal('Test')

  describe "check if tasks are unworked if there is no assigned preset", ->

    describe "POST /v1/queue", ->
      it "should be status/message 'ok'",  (done) ->
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
      it "should be empty object", (done) ->
        Q.delay(1850).then ->
          request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
            check done, ->
              expect(isEmpty(body)).equal(true)

  describe "check adding a preset", ->

    describe "POST /v1/module/preset", ->
      it "should be 1", (done) ->
        options =
          uri: "http://127.0.0.1:1240/v1/module/preset"
          method: "POST"
          json:
            appId: "/app"
            moduleName: "Test"
            status: "enabled"
            options:
              actions:
                add: "Moin, Moin"
                remove: "Tschues"
        request options, (error, req, body) ->
          check done, ->
            expect(body.result.count).equal(1)

    describe "GET /v1/module/preset", ->
      it "should be /app", (done) ->
        request.get "http://127.0.0.1:1240/v1/module/preset", {json: true}, (error, req, body) ->
          check done, ->
            expect(body.Test[0].appId).equal('/app')

    describe "GET /v1/module/preset/Test", ->
      it "should be /app", (done) ->
        request.get "http://127.0.0.1:1240/v1/module/preset/Test", {json: true}, (error, req, body) ->
          check done, ->
            expect(body[0].appId).equal('/app')

  describe "check processing a task in 250ms", ->

    describe "POST task for preset /app to /v1/queue", ->
      it "should be status/message 'ok'", (done) ->
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
    describe "GET /v1/queue", ->
      it "registered module of active task should be Test", (done) ->
        request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
          check done, ->
            expect(body[0].moduleState[0].name).equal('Test')
      it "task state for Test should be started", (done) ->
        request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
          check done, ->
            expect(body[0].moduleState[0].state).equal('started')

    describe "GET /v1/queue", ->
      it "should be empty object", (done) ->
        this.timeout(4500)
        Q.delay(250).then ->
          request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
            check done, ->
              expect(isEmpty(body)).equal(true)

  describe "check removing a preset", ->

    describe "DELETE /v1/module/preset", ->
      it "should be ok", (done) ->
        options =
          uri: "http://127.0.0.1:1240/v1/module/preset"
          method: "DELETE"
          json:
            appId: "/app"
            moduleName: "Test"
        request options, (error, req, body) ->
          check done, ->
            expect(body.result.errors.length).equal(0)

    describe "GET /v1/module/preset", ->
      it "should be empty object", (done) ->
        request.get "http://127.0.0.1:1240/v1/module/preset", {json: true}, (error, req, body) ->
          check done, ->
            expect(isEmpty(body.Test)).equal(true)

  after (done) ->
    this.timeout(6000)
    mconn1.kill()
    Q.delay(5000).then -> done()
