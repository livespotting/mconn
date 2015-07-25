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

Manager = require("./utils/ProcessManager")

createMarathonInventoryItem = require("./utils/Helper").createMarathonInventoryItem
createMarathonRequestdata = require("./utils/Helper").createMarathonRequestdata
createPresetRequestdata = require("./utils/Helper").createPresetRequestdata
webserverIsStarted = require("./utils/Helper").webserverIsStarted
webserverIsKilled = require("./utils/Helper").webserverIsKilled

check = (done, f)  ->
  try
    f()
    done()
  catch e
    done(e)

fakeMarathonInventoryApiIsRunning = false
marathonInventory =
  tasks: []

environment = (processName, port) ->
  name: processName
  MCONN_HOST: "127.0.0.1"
  MCONN_PORT: port
  MCONN_CREDENTIALS: ""
  MCONN_MODULE_PATH: if process.env.MCONN_TEST_MODULE_PATH then process.env.MCONN_TEST_MODULE_PATH else __dirname + "/testmodules"
  MCONN_MODULE_START: process.env.MCONN_TEST_MODULE_START
  MCONN_MODULE_TEST_DELAY: 0
  MCONN_ZK_HOSTS: if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" else "127.0.0.1:2181"
  MCONN_ZK_PATH: "/mconn-dev-synctest"
  MCONN_ZK_SESSION_TIMEOUT: 1000
  MCONN_MARATHON_HOSTS: "localhost:12345"

mconn1 = null

# set env defaults
process.env.MCONN_TEST_MODULE =  if process.env.MCONN_TEST_MODULE then process.env.MCONN_TEST_MODULE  else "Test"

describe "Marathon Sync Test", ->
  before (done) ->
    this.timeout(30000)
    app = express()
    app.get  "/v2/tasks", (req, res) ->
      res.json(marathonInventory)
    app.listen 12345
    mconn1 = new Manager "bin/start.js", environment("MCONN_NODE_1", 1240)
    webserverIsStarted(1240).then ->
      request createPresetRequestdata(1240, "/dev-app-1", process.env.MCONN_TEST_MODULE), (error, req, body) ->
        Q.delay(2000).then ->
          done()

  describe "fakeMarathonInventoryApi", ->
    it "should be reachable on localhost:12345", (done) ->
      request.get "http://127.0.0.1:12345/v2/tasks?status=running", {json: true}, (error, req, body) ->
        if (req.statusCode is 200) then fakeMarathonInventoryApiIsRunning = true
        expect(req.statusCode).equal(200)
        done()

  describe "marathon inventory has 1 element with taskId=A (preset available for this app)", ->
    describe "#{process.env.MCONN_TEST_MODULE} inventory has 0 elements with taskId=A", ->
      describe "check preconditions", ->
        it "should respond with emtpy inventory on GET /v1/modules/inventory/#{process.env.MCONN_TEST_MODULE}", (done) ->
          request.get "http://127.0.0.1:1240/v1/module/inventory/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
            check done, ->
              expect(body.length).equal(0)
        it "should respond with emtpy queue on GET /v1/modules/queue/list/#{process.env.MCONN_TEST_MODULE}", (done) ->
          request.get "http://127.0.0.1:1240/v1/module/queue/list/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
            check done, ->
              expect(body.length).equal(0)

      describe "force sync with GET /v1/modules/sync/#{process.env.MCONN_TEST_MODULE}", ->
        it "should have the missing task in #{process.env.MCONN_TEST_MODULE}Module's inventory after task has been process", (done) ->
          this.timeout(6000)
          expect(fakeMarathonInventoryApiIsRunning).equal(true)
          marathonInventory =
            tasks: [
              createMarathonInventoryItem("A")
            ]
          request.post "http://127.0.0.1:1240/v1/module/sync/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
            Q.delay(5000).then ->
              request.get "http://127.0.0.1:1240/v1/module/inventory/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
                check done, ->
                  expect(body.length).equal(1)
                  expect(body[0].data.taskData.taskId).equal("A")

    describe "marathon inventory has 0 element with taskId=A (preset available for this app)", ->
      describe "#{process.env.MCONN_TEST_MODULE}Modules inventory has 1 elements with taskId=A (from test before)", ->
        it "should remove the wrong task from #{process.env.MCONN_TEST_MODULE}Module's inventory after task has been process", (done) ->
          this.timeout(6000)
          expect(fakeMarathonInventoryApiIsRunning).equal(true)
          marathonInventory =
            tasks: []
          request.post "http://127.0.0.1:1240/v1/module/sync/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
            Q.delay(5000).then ->
              request.get "http://127.0.0.1:1240/v1/module/inventory/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
                check done, ->
                  expect(body.length).equal(0)

  describe "complex syncing test, marathonInventory has tasks [A,B,C], modulesInventory has tasks[D]", ->
    before (done) ->
      request createMarathonRequestdata(1240, "/dev-app-1", "D" + new Date().getTime()), (error, req, body) ->
        Q.delay(3000).then ->
          done()

    describe "force sync with GET /v1/modules/sync/#{process.env.MCONN_TEST_MODULE}", ->
      responseBody = null
      before (done) ->
        this.timeout(6000)
        marathonInventory =
          tasks: [
            createMarathonInventoryItem("A")
            createMarathonInventoryItem("B")
            createMarathonInventoryItem("C")
          ]
        request.post "http://127.0.0.1:1240/v1/module/sync/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
          Q.delay(1000).then ->
            request.get "http://127.0.0.1:1240/v1/module/inventory/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
              responseBody = body
              done()
      it "should have 3 items in inventory", (done) ->
        check done, ->
          expect(responseBody.length).equal(3)
      for i in ["A", "B", "C"]
        do (i) ->
          it "should have task #{i} in inventory", (done) ->
            check done, ->
              found = false
              for item in responseBody
                if item.data.taskData.taskId is i then found = true
              expect(found).equal(true)

  after (done) ->
    this.timeout(6000)
    request createMarathonRequestdata(1240, "/dev-app-1", "A" + new Date().getTime(), "TASK_KILLED"), (error, req, body) ->
      request createMarathonRequestdata(1240, "/dev-app-1", "B" + new Date().getTime(), "TASK_KILLED"), (error, req, body) ->
        request createMarathonRequestdata(1240, "/dev-app-1", "C" + new Date().getTime(), "TASK_KILLED"), (error, req, body) ->
          Q.delay(450).then ->
            mconn1.kill()
            webserverIsKilled(1240).then ->
              done()
