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
check = ( done, f )  ->
  try
    f()
    done()
  catch e
    done(e)
mconn1 = null

describe "WebAPI Tests", ->
  before (done) ->
    this.timeout(30000)
    mconn1 = new Manager("bin/start.js",
      name: "MCONN_NODE_1"
      MCONN_HOST: "127.0.0.1"
      MCONN_PORT: 1240
      MCONN_MODULE_START: ""
      MCONN_MODULE_PATH: __dirname + "/testmodules"
      MCONN_ZK_HOSTS: if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" else "127.0.0.1:2181"
      MCONN_ZK_PATH: "/mconn-dev"
    )
    Q.delay(10000).then -> done()

  describe "GET /v1/queue", ->
    it "should be empty object", (done) ->
      request.get "http://127.0.0.1:1240/v1/queue", {json: true}, (error, req, body) ->
        check done, ->
          expect(isEmpty(body)).equal(true)

  describe "POST /v1/queue", ->
    it "should be status/message 'ok'", (done) ->
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
    it "should be status/message 'warning'", (done) ->
      options =
        uri: "http://127.0.0.1:1240/v1/queue"
        method: "POST"
        json:
          taskId: "app"
          taskStatus: "TASK_RUNNING"
          appId: "/app"
          host: "slave1"
          ports: [1234]
          eventType: "custom_event"
          timestamp: new Date().getTime()
      request options, (error, req, body) ->
        check done, ->
          expect(body.status).equal('warning')

  describe "GET /v1/module/list", ->
    it "should be empty object", (done) ->
      request.get "http://127.0.0.1:1240/v1/module/list", {json: true}, (error, req, body) ->
        check done, ->
          expect(isEmpty(body)).equal(true)

  describe "GET /v1/module/list/HelloWorld", ->
    it "should be status code 500", (done) ->
      request.get "http://127.0.0.1:1240/v1/module/list/HelloWorld", {json: true}, (error, req, body) ->
        check done, ->
          expect(req.statusCode).equal(500)

  describe "POST /v1/module/preset", ->
    it "should be error, Module HelloWorld is not enabled", (done) ->
      options =
        uri: "http://127.0.0.1:1240/v1/module/preset"
        method: "POST"
        json:
          appId: "/app"
          moduleName: "HelloWorld"
          status: "enabled"
          options:
            actions:
              add: "Moin, Moin"
              remove: "Tschues"
      request options, (error, req, body) ->
        check done, ->
          expect(body.result.errors[0]).equal('Module "HelloWorld" is not enabled - skipping preset for app "app"')

  describe "PUT /v1/module/preset", ->
    it "should be error, Module HelloWorld is not enabled", (done) ->
      options =
        uri: "http://127.0.0.1:1240/v1/module/preset"
        method: "PUT"
        json:
          appId: "/app"
          moduleName: "HelloWorld"
          status: "disabled"
      request options, (error, req, body) ->
        check done, ->
          expect(body.result.errors[0]).equal('Module "HelloWorld" is not enabled - skipping preset for app "app"')

  describe "GET /v1/module/preset", ->
    it "should be empty object", (done) ->
      request.get "http://127.0.0.1:1240/v1/module/preset", {json: true}, (error, req, body) ->
        check done, ->
          expect(isEmpty(body)).equal(true)

  describe "DELETE /v1/module/preset", ->
    it "should be error, Module HelloWorld is not enabled", (done) ->
      options =
        uri: "http://127.0.0.1:1240/v1/module/preset"
        method: "DELETE"
        json:
          appId: "/app"
          moduleName: "HelloWorld"
      request options, (error, req, body) ->
        check done, ->
          expect(body.result.errors[0]).equal('Error removing preset /app for  "HelloWorld" "Exception: NO_NODE[-101]": not found')

  describe "GET /v1/module/sync", ->
    it "should be status code 404", (done) ->
      request.get "http://127.0.0.1:1240/v1/module/sync", {json: true}, (error, req, body) ->
        check done, ->
          expect(req.statusCode).equal(404)

  describe "POST /v1/module/sync", ->
    it "should be status code 200", (done) ->
      request.post "http://127.0.0.1:1240/v1/module/sync", {json: true}, (error, req, body) ->
        check done, ->
          expect(req.statusCode).equal(200)

  describe "GET /v1/module/sync/HelloWorld", ->
    it "should be status code 404", (done) ->
      request.get "http://127.0.0.1:1240/v1/module/sync/HelloWorld", {json: true}, (error, req, body) ->
        check done, ->
          expect(req.statusCode).equal(404)

  describe "POST /v1/module/sync/HelloWorld", ->
    it "should be error, Module HelloWorld unkown or not active", (done) ->
      request.post "http://127.0.0.1:1240/v1/module/sync/HelloWorld", {json: true}, (error, req, body) ->
        check done, ->
          expect(body.error).equal('Module HelloWorld unkown or not active')

  describe "GET /v1/info", ->
    body = null
    before (done) ->
      request.get "http://127.0.0.1:1240/v1/info", {json: true}, (error, req, infobody) ->
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
      request.get "http://localhost:1240/v1/leader", {json: true}, (error, req, body) ->
        check done, ->
          expect(body.leader).equal('127.0.0.1:1240')

  describe "GET /v1/ping", ->
    it "should be 'pong'", (done) ->
      request.get "http://127.0.0.1:1240/v1/ping", {json: true}, (error, req, body) ->
        check done, ->
          expect(body).equal('pong')

  describe "GET /v1/exit/node", ->
    it "should be status code 404", (done) ->
      request.get "http://127.0.0.1:1240/v1/exit/node", {json: true}, (error, req, body) ->
        check done, ->
          expect(req.statusCode).equal(404)

  describe "GET /v1/exit/leader", ->
    it "should be status code 404", (done) ->
      request.get "http://127.0.0.1:1240/v1/exit/leader", {json: true}, (error, req, body) ->
        check done, ->
          expect(req.statusCode).equal(404)

  after (done) ->
    this.timeout(6000)
    mconn1.kill()
    Q.delay(5000).then -> done()
