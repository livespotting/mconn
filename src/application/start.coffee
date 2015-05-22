App = require("./App")

MConnJobQueue = require("./classes/MConnJobQueue")

App.checkEnvironment().then ->
  App.initZookeeper()
