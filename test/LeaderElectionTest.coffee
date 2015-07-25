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
request = require("request")
Q = require("q")

MainApp = require("../src/application/App")
Manager = require("./utils/ProcessManager")
QueueManager = require("../src/application/classes/QueueManager")
routes = require("../src/application/webserver/routes/index")
webserverIsStarted = require("./utils/Helper").webserverIsStarted
webserverIsKilled = require("./utils/Helper").webserverIsKilled

QueueManager.createTaskDataForWebview = ->
  return [
    task1: "test"
    task2: "test"
  ]

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
  MCONN_MODULE_PATH: if process.env.MCONN_TEST_MODULE_PATH then process.env.MCONN_TEST_MODULE_PATH else __dirname + "/testmodules"
  MCONN_MODULE_START: process.env.MCONN_TEST_MODULE_START
  MCONN_MODULE_TEST_DELAY: 250
  MCONN_ZK_HOSTS: if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" else "127.0.0.1:2181"
  MCONN_ZK_PATH: "/mconn-leader-test"
  MCONN_ZK_SESSION_TIMEOUT: 250

mconn1 = null
mconn2 = null

describe "Leader Election Tests", ->
  body = null
  before (done) ->
    this.timeout(20000)
    mconn1 = new Manager "bin/start.js", environment("MCONN1", 1240)
    webserverIsStarted(1240)
    .then ->
      mconn2 = new Manager "bin/start.js", environment("MCONN2", 1241)
      webserverIsStarted(1241)
    .then ->
      done()

  describe "check election on startup", ->
    this.timeout(5000)
    it "should return the same result on both nodes", (done) ->
      body1 = null
      body2 = null
      request.get "http://127.0.0.1:1240/v1/leader", {json: true}, (error, req, body) ->
        body1 = body
        request.get "http://127.0.0.1:1241/v1/leader", {json: true}, (error, req, body) ->
          body2 = body
          check done, ->
            expect(body1.leader).equal(body2.leader)

  describe "check election of another leader, if leader has died", ->
    leaderBefore = null
    leaderAfter = null
    processnumberOfLeader = null
    nonleader = null
    describe "exit current leader", ->
      before (done) ->
        this.timeout(10000)
        request.get "http://127.0.0.1:1240/v1/leader", {json: true}, (error, req, body) ->
          leaderBefore = body.leader
          processnumberOfLeader = parseInt(body.leader.split(":")[1]) - 1240
          switch processnumberOfLeader
            when 0
              nonleader = 1241
              mconn1.kill()
            when 1
              nonleader = 1240
              mconn2.kill()
          Q.delay(6500).then ->
            request.get "http://127.0.0.1:#{nonleader}/v1/leader", {json: true}, (error, req, body) ->
              leaderAfter = body.leader
              done()
      it "should elect another leader", ->
        expect(leaderAfter).not.equal(leaderBefore)
      it "should elect the second node as new leader, since it has the smalles id on zk", ->
        expect(leaderAfter).equal("127.0.0.1:#{nonleader}")
      it "should register the new leader to the killed leader, if it comes back to life", (done) ->
        this.timeout(5000)
        mconn1 = new Manager "bin/start.js", environment("MCONN1", 1240)
        webserverIsStarted(1240).then ->
          request.get "http://127.0.0.1:1240/v1/leader", {json: true}, (error, req, body) ->
            check done, ->
              expect(body.leader).equal(leaderAfter)

  after (done) ->
    mconn1.kill()
    mconn2.kill()
    webserverIsKilled(1240).then ->
      webserverIsKilled(1241).then ->
        done()
