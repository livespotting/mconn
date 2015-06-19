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
deferred = Q.defer()
module.exports = deferred

MainApp = require("../src/application/App")
Manager = require("./utils/ProcessManager")
QueueManager = require("../src/application/classes/QueueManager")
routes = require("../src/application/webserver/routes/index")

QueueManager.createTaskDataForWebview = ->
  return [
    task1: "test"
    task2: "test"
  ]

check = ( done, f )  ->
  try
    f()
    done()
  catch e
    done(e)
mconn1 = null
mconn2 = null
mconn3 = null

describe "Leader Election Tests", ->
  body = null
  before (done) ->
    this.timeout(50000)
    mconn1 = new Manager("bin/start.js",
      name: "MCONN_NODE_1"
      MCONN_HOST: "127.0.0.1"
      MCONN_PORT: 1240
      MCONN_MODULE_START: ""
      MCONN_MODULE_PATH: __dirname + "/testmodules"
      MCONN_ZK_HOSTS: if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" else "127.0.0.1:2181"
      MCONN_ZK_PATH: "/mconn-dev"
    )
    Q.delay(10000)
    .then ->
      mconn2 = new Manager("bin/start.js",
        name: "MCONN_NODE_2"
        MCONN_HOST: "127.0.0.1"
        MCONN_PORT: 1241
        MCONN_MODULE_START: ""
        MCONN_MODULE_PATH: __dirname + "/testmodules"
        MCONN_ZK_HOSTS: if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" else "127.0.0.1:2181"
        MCONN_ZK_PATH: "/mconn-dev"
      )
      return Q.resolve()
    .delay(10000)
    .then ->
      mconn3 = new Manager("bin/start.js",
        name: "MCONN_NODE_3"
        MCONN_HOST: "127.0.0.1"
        MCONN_PORT: 1242
        MCONN_MODULE_START: ""
        MCONN_MODULE_PATH: __dirname + "/testmodules"
        MCONN_ZK_HOSTS: if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" else "127.0.0.1:2181"
        MCONN_ZK_PATH: "/mconn-dev"
      )
      return Q.resolve()
    .delay(10000)
    .then -> done()

  describe "check first startup election", ->
    it "should return the same result for all three nodes", (done) ->
      this.timeout(5000)
      body1 = null
      body2 = null
      body3 = null
      request.get "http://127.0.0.1:1240/v1/leader", {json: true}, (error, req, body) ->
        body1 = body
        request.get "http://127.0.0.1:1241/v1/leader", {json: true}, (error, req, body) ->
          body2 = body
          request.get "http://127.0.0.1:1242/v1/leader", {json: true}, (error, req, body) ->
            body3 = body
            check done, ->
              expect(body1.leader).equal(body2.leader)
              expect(body1.leader).equal(body3.leader)

  describe "check follower to leader election", ->
    leaderBefore = null
    leaderAfter1 = null
    leaderAfter2 = null

    describe "exit current leader", ->
      before (done) ->
        this.timeout(15000)
        request.get "http://127.0.0.1:1240/v1/leader", {json: true}, (error, req, body) ->
          leaderBefore = body.leader
          request.post "http://127.0.0.1:1242/v1/exit/leader", {json: true}, (error, req, body) ->
            Q.delay(10000).then ->
              request.get "http://127.0.0.1:1241/v1/leader", {json: true}, (error, req, body) ->
                leaderAfter1 = body.leader
                request.get "http://127.0.0.1:1242/v1/leader", {json: true}, (error, req, body) ->
                  leaderAfter2 = body.leader
                  done()
      it "should elect another leader", ->
        expect(leaderAfter1).not.equal(leaderBefore)
      it "should have the same leader for both of the remaining mconn-nodes", ->
        expect(leaderAfter1).equal(leaderAfter2)
      it "should elect the second node as new leader, since it has the smalles id on zk", ->
        expect(leaderAfter1).equal("127.0.0.1:1241")
      it "should register the new leader to the killed leader, if it comes back to life", (done) ->
        request.get "http://127.0.0.1:1240/v1/leader", {json: true}, (error, req, body) ->
          check done, ->
            expect(body.leader).equal(leaderAfter1)

  after (done) ->
    this.timeout(7500)
    mconn1.kill()
    mconn2.kill()
    mconn3.kill()
    Q.delay(5000).then ->
      deferred.resolve()
      done()
