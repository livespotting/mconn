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
sinon = require 'sinon'
sinonChai = require 'sinon-chai'
chai.use sinonChai
expect = chai.expect
express = require("express")
http = require('http')
request = require("request")
Q = require("q")

Middlewares = require("../src/application/classes/Middlewares")
routes = require("../src/application/webserver/routes/index")
MainApp = require("../src/application/App")

check = (done, f)  ->
  try
    f()
    done()
  catch e
    done(e)

describe "Middlewares", ->
  describe "appendMasterDataToRequest", ->
    server = null
    app = null
    # BEFORE EACH -> start a webserver on port 11223 and
    # overwrite methods, that depend from other units of
    # the application like
    # - ZookeeperHandler -> depends on running zookeeper
    # - getModules -> depends on Moduleloader
    beforeEach ->
      app = express()
      # return 'master' on ZookeeperHandler's getMasterData()
      Middlewares.ZookeeperHandler = ->
        return {
        getMasterData: ->
          Q.resolve("master")
        }
      # return fake list of loaded modules
      Middlewares.getModules = ->
        return ["ModuleA", "ModuleB", "ModuleC"]
      #register appendMasterDataToRequest middleware
      app.use "/", Middlewares.appendMasterDataToRequest
      server = http.createServer(app).listen(11223)
    it "should append masterdata to response locals", (done) ->
      app.get "/appendMasterdata", (req, res) ->
        check done, ->
          expect(res.locals.mconnenv.masterdata).equal("master")
        res.end()
      request.get "http://localhost:11223/appendMasterdata"
    it "should append all activated Modules to response locals", (done) ->
      app.get "/appendActivatedModules", (req, res) ->
        check done, ->
          expect(res.locals.mconnenv.activatedModules.length).equal(3)
          expect(res.locals.mconnenv.activatedModules[1]).equal("ModuleB")
      request.get "http://localhost:11223/appendActivatedModules"
    it "should append version to response locals", (done) ->
      app.get "/version", (req, res) ->
        check done, ->
          expect(res.locals.mconnenv.version).equal(process.env.npm_package_version)
        res.end()
      request.get "http://localhost:11223/version"
    afterEach ->
      server.close()

  describe "checkRequestIsValid", ->
    it "should not redirect to following middlewares, if eventType isnt 'status_update_event' or 'scheduler_registered_event'", ->
      spy = sinon.spy()
      testRequest =
        body:
          eventType: "anyother"
      testResponse =
        json: -> null
      Middlewares.checkRequestIsValid(testRequest, testResponse, spy)
      expect(spy).not.to.have.been.called
    it "should redirect to following middlewares, if eventType is 'status_update_event'", ->
      spy = sinon.spy()
      testRequest =
        body:
          eventType: "status_update_event"
      testResponse =
        json: -> null
      Middlewares.checkRequestIsValid(testRequest, testResponse, spy)
      expect(spy).to.have.been.called
    it "should redirect to following middlewares, if eventType is 'scheduler_registered_event'", ->
      spy = sinon.spy()
      testRequest =
        body:
          eventType: "scheduler_registered_event"
      testResponse =
        json: -> null
      Middlewares.checkRequestIsValid(testRequest, testResponse, spy)
      expect(spy).to.have.been.called

  describe "route", ->
    res = null
    mockZookeeperHandler = null
    before ->
      # mock response with serverurl added
      res =
        locals:
          mconnenv:
            masterdata:
              serverdata:
                serverurl: "http://localhost:11224"
      mockZookeeperHandler = require("./utils/Helper").mockZookeeperHandler()
      mockZookeeperHandler.isMaster = true
      Middlewares.ZookeeperHandler = -> mockZookeeperHandler

    describe "requested server is the leader", ->
      it "should lead request to next Middleware without proxying", ->
        next = sinon.spy()
        Middlewares.route({}, res, next)
        expect(next).to.have.been.called

    describe "requested server is not the leader", ->
      it "should not lead request to next Middleware", ->
        mockZookeeperHandler.isMaster = false
        next = sinon.spy()
        doProxyRequest = sinon.stub(Middlewares, "doProxyRequest")
        Middlewares.route({}, res, next)
        expect(next).not.to.have.been.called
        doProxyRequest.restore()

      it "should proxy request to leader", ->
        mockZookeeperHandler.isMaster = false
        next = sinon.spy()
        doProxyRequest = sinon.stub(Middlewares, "doProxyRequest")
        Middlewares.route({}, res, next)
        expect(doProxyRequest).to.have.been.called

      describe "- leader has the same address as requested server -", ->
        it "should end request", ->
          mockZookeeperHandler.isMaster = false
          next = sinon.spy()
          res.end = sinon.spy()
          leaderIsOwnServer = sinon.stub(Middlewares, "leaderIsOwnServer")
          leaderIsOwnServer.returns(true)
          Middlewares.route({}, res, next)
          expect(res.end).to.have.been.called
          leaderIsOwnServer.restore()
        it "should return statusCode 404", ->
          mockZookeeperHandler.isMaster = false
          next = sinon.spy()
          leaderIsOwnServer = sinon.stub(Middlewares, "leaderIsOwnServer")
          leaderIsOwnServer.returns(true)
          Middlewares.route({}, res, next)
          expect(res.statusCode).to.equal(404)
