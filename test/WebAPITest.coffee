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

createMarathonRequestdata = require("./utils/Helper").createMarathonRequestdata
createPresetRequestdata = require("./utils/Helper").createPresetRequestdata
webserverIsStarted = require("./utils/Helper").webserverIsStarted
webserverIsKilled = require("./utils/Helper").webserverIsKilled

isEmpty = (obj) ->
  for k of obj
    if obj.hasOwnProperty(k)
      return false
  true

check = (done, f)  ->
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
  MCONN_MODULE_PATH: ""
  MCONN_MODULE_START: ""
  MCONN_MODULE_TEST_DELAY: 250
  MCONN_ZK_HOSTS: if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" else "127.0.0.1:2181"
  MCONN_ZK_PATH: "/mconn-dev-webapi"
  MCONN_ZK_SESSION_TIMEOUT: 1000

mconn1 = null

getShouldBeAnEmtpyObjectOrArray = [
  "/v1/queue"
  "/v1/module/list"
  "/v1/module/preset"
]
getShouldBeModuleNotFound = [
  "/v1/module/inventory/Test"
  "/v1/module/list/Test"
  "/v1/module/queue/list/Test"
  "/v1/module/preset/Test"
]
postShouldBeModuleNotFound = [
  "/v1/module/queue/pause/Test"
  "/v1/module/queue/resume/Test"
  "/v1/module/sync/Test"
]
getShouldBe200 = [
  "/v1/queue"
  "/v1/module/list"
  "/v1/module/preset"
  "/v1/info"
  "/v1/leader"
  "/v1/ping"
]
getShouldBe404 = [
  "/v1/module/inventory/Test"
  "/v1/module/list/Test"
  "/v1/module/queue/list/Test"
  "/v1/module/preset/Test"
  "/v1/module/sync"
  "/v1/exit/leader"
  "/v1/exit/node"
]
postShouldBe200 = [
  "/v1/queue"
  "/v1/module/preset"
  "/v1/module/sync"
]
postShouldBe404 = [
  "/v1/module/inventory/Test"
  "/v1/module/list"
  "/v1/module/queue/list"
  "/v1/module/queue/pause/Test"
  "/v1/module/queue/resume/Test"
  "/v1/module/sync/Test"
  "/v1/info"
  "/v1/leader"
  "/v1/ping"
]
putShouldBe200 = [
  "/v1/module/preset"
]
putShouldBe404 = [
  "/v1/queue"
  "/v1/module/inventoy"
  "/v1/module/list"
  "/v1/module/queue/list"
  "/v1/module/sync"
  "/v1/info"
  "/v1/leader"
  "/v1/ping"
  "/v1/exit/leader"
  "/v1/exit/node"
]
deleteShouldBe200 = [
  "/v1/module/preset"
]
deleteShouldBe404 = [
  "/v1/queue"
  "/v1/module/inventory"
  "/v1/module/list"
  "/v1/module/queue/list"
  "/v1/module/sync"
  "/v1/info"
  "/v1/leader"
  "/v1/ping"
  "/v1/exit/leader"
  "/v1/exit/node"
]

describe "WebAPI Tests", ->
  before (done) ->
    this.timeout(60000)
    mconn1 = new Manager "bin/start.js", environment("MCONN_NODE_1", 1255)
    webserverIsStarted(1255).then ->
      done()

  describe "test message", ->
    describe "GET", ->
      for url in getShouldBeAnEmtpyObjectOrArray
        do (url) ->
          it "should return an empty object or array #{url}", (done) ->
            request.get "http://127.0.0.1:1255" + url, {json: true}, (error, req, body) ->
              check done, ->
                expect(isEmpty(body)).equal(true, "body is " + JSON.stringify(body))
      for url in getShouldBeModuleNotFound
        do (url) ->
          it "should return status \"error\" and \"Module not found\" #{url}", (done) ->
            request.get "http://127.0.0.1:1255" + url, {json: true}, (error, req, body) ->
              check done, ->
                expect(body.status).equal('error')
                expect(body.message).equal('Module not found: Test')

    describe "POST", ->
      for url in postShouldBeModuleNotFound
        do (url) ->
          it "should return status \"error\" and \"Module not found\" #{url}", (done) ->
            request.post "http://127.0.0.1:1255" + url, {json: true}, (error, req, body) ->
              check done, ->
                expect(body.status).equal('error')
                expect(body.message).equal('Module not found: Test')

  describe "test custom or complex message", ->
    describe "POST valid task to /v1/queue", ->
      it "should return taskId 'app_1234_TASK_RUNNING' and leader 'http://127.0.0.1:1255", (done) ->
        request createMarathonRequestdata(1255, "/app", "app_1234"), (error, req, body) ->
          check done, ->
            expect(body.leader).equal('http://127.0.0.1:1255')
            expect(body.taskId).equal('app_1234_TASK_RUNNING')

    describe "POST invalid task (unknown eventType) to /v1/queue", ->
      it "should return status \"error\" and message 'rejected'", (done) ->
        request createMarathonRequestdata(1255, "/app", "app_" + new Date().getTime(), "TASK_RUNNING", "custom_event"), (error, req, body) ->
          check done, ->
            expect(body.status).equal('error')
            expect(body.message).equal('EventType has been rejected: custom_event')

    describe "POST /v1/module/preset", ->
      it "should return status \"error\" and \"Module not found\"'", (done) ->
        request createPresetRequestdata(1255, "/app", "Test"), (error, req, body) ->
          check done, ->
            expect(body.status).equal('error')
            expect(body.message).equal('Module not found: Test')

    describe "PUT /v1/module/preset", ->
      it "should return status \"error\" and \"Module not found\"'", (done) ->
        request createPresetRequestdata(1255, "/app", "Test", "disabled", "PUT"), (error, req, body) ->
          check done, ->
            expect(body.status).equal('error')
            expect(body.message).equal('Module not found: Test')


    describe "GET /v1/info", ->
      body = null
      before (done) ->
        request.get "http://127.0.0.1:1255/v1/info", {json: true}, (error, req, infobody) ->
          body = infobody
          done()
      vars = MainApp.env_vars
      for e in vars
        do (e) ->
          it "should return env " + e.name, (done) ->
            check done, ->
              expect(body.env[e.name]?).equal(true)
      it "should return the current leader", (done) ->
        check done, ->
          expect(body.leader?).equal(true)

    describe "GET /v1/leader", ->
      it "should return the current leader", (done) ->
        request.get "http://localhost:1255/v1/leader", {json: true}, (error, req, body) ->
          check done, ->
            expect(body.leader).equal('127.0.0.1:1255')

    describe "GET /v1/ping", ->
      it "should be 'pong'", (done) ->
        request.get "http://127.0.0.1:1255/v1/ping", {json: true}, (error, req, body) ->
          check done, ->
            expect(body).equal('pong')

  describe "test status codes", ->
    describe "GET", ->
      for url in getShouldBe200
        do (url) ->
          it "should return statusCode 200 on #{url}", (done) ->
            request.get "http://127.0.0.1:1255" + url, {json: true}, (error, req, body) ->
              check done, ->
                expect(req.statusCode).equal(200)
      for url in getShouldBe404
        do (url) ->
          it "should return statusCode 404 on #{url}", (done) ->
            request.get "http://127.0.0.1:1255" + url, {json: true}, (error, req, body) ->
              check done, ->
                expect(req.statusCode).equal(404)

    describe "POST", ->
      for url in postShouldBe200
        do (url) ->
          it "should return statusCode 200 on #{url}", (done) ->
            request.post "http://127.0.0.1:1255" + url, {json: true}, (error, req, body) ->
              check done, ->
                expect(req.statusCode).equal(200)
      for url in postShouldBe404
        do (url) ->
          it "should return statusCode 404 on #{url}", (done) ->
            request.post "http://127.0.0.1:1255" + url, {json: true}, (error, req, body) ->
              check done, ->
                expect(req.statusCode).equal(404)

    describe "PUT", ->
      for url in putShouldBe200
        do (url) ->
          it "should return statusCode 200 on #{url}", (done) ->
            request.put "http://127.0.0.1:1255" + url, {json: true}, (error, req, body) ->
              check done, ->
                expect(req.statusCode).equal(200)
      for url in putShouldBe404
        do (url) ->
          it "should return statusCode 404 on #{url}", (done) ->
            request.put "http://127.0.0.1:1255" + url, {json: true}, (error, req, body) ->
              check done, ->
                expect(req.statusCode).equal(404)

    describe "DELETE", ->
      for url in deleteShouldBe200
        do (url) ->
          it "should return statusCode 200 on #{url}", (done) ->
            request.del "http://127.0.0.1:1255" + url, {json: true}, (error, req, body) ->
              check done, ->
                expect(req.statusCode).equal(200)
      for url in deleteShouldBe404
        do (url) ->
          it "should return statusCode 404 on #{url}", (done) ->
            request.del "http://127.0.0.1:1255" + url, {json: true}, (error, req, body) ->
              check done, ->
                expect(req.statusCode).equal(404)

  after (done) ->
    this.timeout(6000)
    mconn1.kill()
    webserverIsKilled(1255).then ->
      done()
