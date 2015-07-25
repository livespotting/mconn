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

# helper to imediatly carry on after a webserver has started
createMarathonRequestdata = require("./utils/Helper").createMarathonRequestdata
createPresetRequestdata = require("./utils/Helper").createPresetRequestdata
webserverIsStarted = require("./utils/Helper").webserverIsStarted
webserverIsKilled = require("./utils/Helper").webserverIsKilled

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

environment = (processName, port) ->
  name: processName
  MCONN_HOST: "127.0.0.1"
  MCONN_PORT: port
  MCONN_CREDENTIALS: "admin:password"
  MCONN_MODULE_PATH: if process.env.MCONN_TEST_MODULE_PATH then process.env.MCONN_TEST_MODULE_PATH else __dirname + "/testmodules"
  MCONN_MODULE_START: process.env.MCONN_TEST_MODULE_START
  MCONN_MODULE_TEST_DELAY: 250
  MCONN_ZK_HOSTS: if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" else "127.0.0.1:2181"
  MCONN_ZK_PATH: "/mconn-dev-credentials-1"
  MCONN_ZK_SESSION_TIMEOUT: 1000

allowedWithoutCredentials = [
  "/v1/ping"
]
notAllowedWithoutCredentials = [
  "/v1/queue"
  "/v1/module/inventory/Test"
  "/v1/module/list"
  "/v1/module/list/Test"
  "/v1/module/queue/list/Test"
  "/v1/module/preset"
  "/v1/module/preset/Test"
  "/v1/info"
  "/v1/leader"
]

mconn1 = null
mconn2 = null
mconn3 = null
mconn4 = null
mconn5 = null

describe "Credentials Test", ->
  body = null
  describe "test with 3 nodes", ->
    before (done) ->
      this.timeout(60000)
      mconn1 = new Manager "bin/start.js", environment("MCONN_NODE_1", 1250)
      webserverIsStarted(1250)
      .then ->
        mconn2 = new Manager "bin/start.js", environment("MCONN_NODE_2", 1251)
        webserverIsStarted(1251)
      .then ->
        mconn3 = new Manager "bin/start.js", environment("MCONN_NODE_3", 1252)
        webserverIsStarted(1252)
      .then ->
        done()

    describe "check if the non-leaders can proxy apicalls to the leader with correct MCONN_CREDENTIALS", ->
      before (done) ->
        request createPresetRequestdata(1250, "/app", "Test", "enabled", "POST", "admin:password@127.0.0.1"), (error, req, body) ->
          done()
      it "should return more then 0 tasks on leaders queue", (done) ->
        request createMarathonRequestdata(1250, "/app", "app" + new Date().getTime()), (error, req, body) ->
          request createMarathonRequestdata(1251, "/app", "app" + new Date().getTime()), (error, req, body) ->
            request createMarathonRequestdata(1252, "/app", "app" + new Date().getTime()), (error, req, body) ->
              request.get "http://admin:password@127.0.0.1:1250/v1/queue", {json: true}, (error, req, body) ->
                check done, ->
                  expect(body.length).not.to.equal(0)

    describe "check rights-management of webapi-urls", ->
      describe "test unallowed urls", ->
        describe "calls without credentials", ->
          for url in notAllowedWithoutCredentials
            do (url) ->
              it "should return statusCode 401 on #{url}", (done) ->
                request.get "http://127.0.0.1:1250" + url, {json: true}, (error, req, body) ->
                  check done, ->
                    expect(req.statusCode).equal(401)
        describe "calls with credentials", ->
          for url in notAllowedWithoutCredentials
            do (url) ->
            it "should return statusCode 200 on #{url} if using credentials", (done) ->
              request.get "http://admin:password@127.0.0.1:1250" + url, {json: true}, (error, req, body) ->
                check done, ->
                  expect(req.statusCode).equal(200)

      describe "test allowed urls", ->
        for url in allowedWithoutCredentials
          do (url) ->
            it "should return statusCode 200 on #{url}", (done) ->
              request.get "http://127.0.0.1:1250" + url, {json: true}, (error, req, body) ->
                check done, ->
                  expect(req.statusCode).equal(200)
    after (done) ->
      mconn1.kill()
      mconn2.kill()
      mconn3.kill()
      done()

  describe "check that basicAuth is disabled, if credentials do not have the right format", ->
    invalidFormats = [
      "admin"
      "admin:a:a"
      ""
    ]
    i = 4 #just to define ports that defer from tests before
    for format in invalidFormats
      do (format) ->
        describe "checking invalid format " + format, ->
          mconn = null
          port = 1250 + i
          before (done) ->
            envForMconn = environment("MCONN_NODE", port)
            envForMconn.MCONN_CREDENTIALS = format
            envForMconn.MCONN_ZK_PATH = "/mconn-dev-credentials-" + i
            mconn = new Manager("bin/start.js", envForMconn)
            webserverIsStarted(port).then ->
              done()
          it "should return an 200 on /v1/info without using credentials (basicAuth disabled)", (done) ->
            request.get "http://127.0.0.1:#{port}/v1/info", {json: true}, (error, req, body) ->
              check done, ->
                expect(req.statusCode).equal(200)
          after (done) ->
            mconn.kill()
            i++
            webserverIsKilled(1250).then ->
              done()
