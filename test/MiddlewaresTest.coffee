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

Middlewares = require("../src/application/classes/Middlewares")
routes = require("../src/application/webserver/routes/index")
MainApp = require("../src/application/App")

check = ( done, f )  ->
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
      spy = chai.spy()
      testRequest =
        body:
          eventType: "anyother"
      testResponse =
        json: -> null
      Middlewares.checkRequestIsValid(testRequest, testResponse, spy)
      expect(spy).not.to.have.been.called()
    it "should redirect to following middlewares, if eventType is 'status_update_event'", ->
      spy = chai.spy()
      testRequest =
        body:
          eventType: "status_update_event"
      testResponse =
        json: -> null
      Middlewares.checkRequestIsValid(testRequest, testResponse, spy)
      expect(spy).to.have.been.called()
    it "should redirect to following middlewares, if eventType is 'scheduler_registered_event'", ->
      spy = chai.spy()
      testRequest =
        body:
          eventType: "scheduler_registered_event"
      testResponse =
        json: -> null
      Middlewares.checkRequestIsValid(testRequest, testResponse, spy)
      expect(spy).to.have.been.called()

  describe "route", ->
    server = null
    server2 = null
    app = null
    app2 = null
    beforeEach ->
      #source server
      app = express()
      app.use bodyParser.json()
      app.use bodyParser.urlencoded({extended: true})
      app.use "/", (req, res, next ) ->
        # fake setting of masterserverurl by middleware 'appendMasterDataToRequest'
        res.locals =
          mconnenv:
            masterdata:
              serverdata:
                serverurl: "http://localhost:11224"
        next()
      app.use "/v1", Middlewares.route
      server = http.createServer(app).listen(11223)
      #destination server
      app2 = express()
      app2.use bodyParser.json()
      app2.use bodyParser.urlencoded({extended: true})
      server2 = http.createServer(app2).listen(11224)

    it "should redirect any GET requests to masterserver with same url", (done) ->
      #check if proxied request is incoming on server2 :11224
      app2.get "/v1/anyurl", (req, res) ->
        check done, ->
          expect(true).equal(true)
      request.get "http://localhost:11223/v1/anyurl"
    it "should redirect any POST requests to masterserver with same url", (done) ->
      app2.post "/v1/anyurl", (req, res) ->
        check done, ->
          expect(true).equal(true)
      request.post "http://localhost:11223/v1/anyurl"
    it "should append the original body", (done) ->
      #check if proxied request is incoming on server2 :11224
      app2.post "/v1/queue", (req, res) ->
        check done, ->
          expect(req.body.myFunkyParameter).equal("funk is in the house")
      options =
        uri: "http://localhost:11223/v1/queue"
        method: "POST"
        json:
          myFunkyParameter: "funk is in the house"
      request options

    afterEach ->
      server.close()
      server2.close()
