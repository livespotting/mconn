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
  MCONN_ZK_PATH: "/mconn-dev-multihost"
  MCONN_ZK_SESSION_TIMEOUT: 1000
  MCONN_MARATHON_HOSTS: "localhost:12343,localhost:12344,localhost:12346"

mconn1 = null

# set env defaults
process.env.MCONN_TEST_MODULE = if process.env.MCONN_TEST_MODULE then process.env.MCONN_TEST_MODULE  else "Test"

describe "Marathon Multihost Test", ->
  before (done) ->
    this.timeout(60000)
    mconn1 = new Manager "bin/start.js", environment("MCONN_NODE_1", 1260)
    webserverIsStarted(1260).then ->
      request createPresetRequestdata(1260, "/dev-app-1", process.env.MCONN_TEST_MODULE), (error, req, body) ->
        Q.delay(2000).then ->
          request.post "http://127.0.0.1:1260/v1/module/sync/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
            Q.delay(5000).then ->
              app = express()
              app.get  "/v2/tasks", (req, res) ->
                res.json(marathonInventory)
              app.listen 12346
              done()

  describe "fakeMarathonInventoryApi", ->
    it "should be reachable on localhost:12346", (done) ->
      request.get "http://127.0.0.1:12346/v2/tasks?status=running", {json: true}, (error, req, body) ->
        if (req.statusCode is 200) then fakeMarathonInventoryApiIsRunning = true
        expect(req.statusCode).equal(200)
        done()

  describe "force sync with POST /v1/modules/sync/#{process.env.MCONN_TEST_MODULE}", ->
    it "should have the missing task in #{process.env.MCONN_TEST_MODULE} Module's inventory after task has been processed by the third marathon host", (done) ->
      this.timeout(6000)
      expect(fakeMarathonInventoryApiIsRunning).equal(true)
      marathonInventory =
        tasks: [
          createMarathonInventoryItem("A")
        ]
      request.post "http://127.0.0.1:1260/v1/module/sync/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
        Q.delay(5000).then ->
          request.get "http://127.0.0.1:1260/v1/module/inventory/#{process.env.MCONN_TEST_MODULE}", {json: true}, (error, req, body) ->
            check done, ->
              expect(body.length).equal(1)
              expect(body[0].data.taskData.taskId).equal("A")

  after (done) ->
    this.timeout(6000)
    request createMarathonRequestdata(1250, "/dev-app-1", "A" + new Date().getTime(), "TASK_KILLED"), (error, req, body) ->
      Q.delay(150).then ->
        mconn1.kill()
        webserverIsKilled(1250).then ->
          done()
