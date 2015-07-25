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

App = require("./App")
require("./webserver/config/config")
logger = require("./classes/Logger")("Startprocess")
QueueManager = require("./classes/QueueManager")

App.checkEnvironment()
.then ->
  App.initZookeeper()
.then ->
  App.initModules()
.then ->
  App.startWebserver()
.catch (error) ->
  logger.error(error, error.stack)
