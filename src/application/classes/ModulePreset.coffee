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

async = require("async")
Q = require("q")
zookeeper = require("node-zookeeper-client")

Module = require("./Module")
logger = require("./Logger")("ModulePreset")
ZookeeperHandler = require("./ZookeeperHandler")

# Manager to manage all presets
# Everytime Marathon pushes a config to the apiurl, the request comes with the appId of the app that was scaled
# These preset are used to tell the modules, what to do with this app. If i.E. app-dev-1 is pushed to server
# my-server-1, then this config could consist of port-to-servicegroup mappings
#
class ModulePreset

  # filesystemhandler
  @fs: require("q-io/fs")

  # read preset from filesystem
  #
  # @return [Promise] resolves with array of filecontents
  #
  @readPresetFromFS: =>
    self = @
    deferred = Q.defer()
    self.fs.listTree(process.env.MCONN_PRESET_DIR)
    .then (result) ->
      result.splice(0,1) #remove root folder in array
      fileContents = []
      async.eachLimit(
        result, 1
      ,(path, done) ->
        self.fs.read(path)
        .then (content) ->
          fileContents.push(JSON.parse(content))
        .catch (error) ->
          logger.error("Error reading preset " + error.toString(), error.stack)
        .finally -> done()
      , ->
        deferred.resolve(fileContents)
      )
    .catch (error) ->
      logger.error(error, error.stack)
    deferred.promise

  # read available presets from zookeeper
  #
  # @return [Promise] resolves with list of presets
  #
  @readConfigsFromZookeeper: ->
    return ZookeeperHandler.getChildren("presets")

  # determines diff between return of presetSourceMethod and active zookeeper storage and
  # creates an array of presets, that have not yet been added to zookeeper
  #
  # @param [Function] presetSourceMethod has to be a promise returning method, that resolves with an array
  # of the presets [{appId: dev-app-1, options:{}...},{appId: dev-app-2 ...]
  #
  # @return array of presets to push to zookeeper
  #
  @diff: (presetSourceMethod, allwaysUpdate = false) ->
    deferred = Q.defer()
    sourceContents = null
    presetSourceMethod()
    .then (sourceContents) ->
      pushToZookeeper = []
      async.eachLimit(sourceContents,1, (sc, done) ->
        appid = sc.appId.split("/")[1]
        ZookeeperHandler.exists("modules/#{sc.moduleName}/presets/#{appid}")
        .then (exists) ->
          if allwaysUpdate and exists
            logger.info "Update preset \"#{sc.appId}\" for module \"#{sc.moduleName}\""
            sc.lastEdit = new Date().getTime()
            pushToZookeeper.push(sc)
          else unless exists
            logger.info "Create preset \"#{sc.appId}\"for module \"#{sc.moduleName}\""
            sc.lastEdit = false
            pushToZookeeper.push(sc)
        .catch (error) ->
          logger.error("Create error \"" + error + "\"", error.stack)
        .finally ->
          done()
      , ->
        deferred.resolve(pushToZookeeper)
      )
    .catch (error) ->
      logger.error("Create error \"" + error.toString() + " " + "\"", error.stack)
      deferred.reject(error)
    deferred.promise

  # syncs difference between presetSourceMethod and active zk storage on zk storage
  #
  # @param [Function] presetSourceMethod has to be a promise returning method, that resolves with an array
  # of the presets [{appId: dev-app-1, options:{}...},{appId: dev-app-2 ...]
  #
  # @return [Number] number of written preset
  #
  @sync: (presetSourceMethod, allwaysUpdate = false) ->
    deferred = Q.defer()
    errors = []
    count = 0
    @diff(presetSourceMethod, allwaysUpdate)
    .then (result) =>
      async.each(result,
        (preset, done) =>
          clearedAppName = preset.appId.split("/")[1]
          Module = require("./Module")
          unless Module.isEnabled(preset.moduleName)
            message = "Module \"#{preset.moduleName}\" is not enabled - skipping preset for app \"#{clearedAppName}\""
            logger.error(message, "")
            errors.push(message)
            done()
          else
            count++
            if preset.lastEdit
              @editPreset(preset, clearedAppName, done)
            else
              @createPreset(preset, clearedAppName, done)
        , ->
          deferred.resolve(
            count: count
            errors: errors
          )
      )
    .catch (error) ->
      logger.error(error, error.stack)
    deferred.promise

  @editPreset: (preset, clearedAppName, done) ->
    deferred = Q.defer()
    logger.info("Forward preset update \"#{clearedAppName}\" for module \"#{preset.moduleName}\" to
                ZookeeperHandler")
    ZookeeperHandler.setData("modules/#{preset.moduleName}/presets/#{clearedAppName}",preset)
    .then ->
      Module.modules[preset.moduleName].updatePresetsOnGui()
      Module.modules[preset.moduleName].editPreset(preset)
      deferred.resolve()
    .catch (error) ->
      logger.error(error, error.stack)
      deferred.reject(error)
    .finally ->
      done()
    deferred.promise

  @createPreset: (preset, clearedAppName, done) ->
    deferred = Q.defer()
    logger.info("Forward preset creation \"#{clearedAppName}\" for module \"#{preset.moduleName}\" to
                ZookeeperHandler")
    ZookeeperHandler.createNode("modules/#{preset.moduleName}/presets/#{clearedAppName}",
      new Buffer(JSON.stringify(preset)), zookeeper.ACL.OPEN, zookeeper.CreateMode.PERSISTENT)
    .then ->
      Module.modules[preset.moduleName].updatePresetsOnGui()
      Module.modules[preset.moduleName].createPreset(preset)
      deferred.resolve()
    .catch (error) ->
      deferred.reject(error)
    .finally ->
      done()
    deferred.promise

  # removes presets from zookeeper
  #
  # @param [Array] presets array of presets
  #
  # @return [Promise] resolves with nothing
  #
  @remove: (presets) ->
    deferred = Q.defer()
    errors = []
    async.each(presets,
      (preset, done) ->
        clearedAppName = preset.appId.split("/")[1]
        logger.warn("Remove preset \"" + preset.appId + "\" for module \"#{preset.moduleName}\"")
        ZookeeperHandler.remove("modules/#{preset.moduleName}/presets/#{clearedAppName}")
        .then ->
          Module.modules[preset.moduleName].deletePreset(preset)
        .catch (error) ->
          message = "Error removing preset #{preset.appId} for  \"" + preset.moduleName + "\" \"" + error.toString() +  "\": not found"
          errors.push message
          logger.error(message, "")
        .finally ->
          done()
      , ->
        deferred.resolve(
          errors: errors
        )
    )
    deferred.promise

  # get all presets of all modules
  #
  # @return [Promise] resolves with presets
  #
  @getAllFromZookeeper: ->
    deferred = Q.defer()
    modules = require("../classes/Module").modules
    presets = {}
    modulenames = []
    for modulename, module of modules
      modulenames.push(modulename)
    async.each(modulenames,
      (module, done) =>
        @getAllOfModuleFromZookeeper(module)
        .then (modulepresets) ->
          presets[module] = modulepresets
          done()
        .catch (error) ->
          logger.error(error, error.stack)
    ,
      ->
        deferred.resolve(presets)
    )
    deferred.promise

  @getAll: ->
    modules = require("../classes/Module").modules
    presets = {}
    for modulename, module of modules
      presets[modulename] = module.presets
    return Q.resolve(presets)

  # get all presets of a given module
  #
  # @param [String] moduleName
  #
  # @return [Promise]
  #
  @getAllOfModuleFromZookeeper: (moduleName) ->
    deferred = Q.defer()
    ZookeeperHandler.getChildren("modules/#{moduleName}/presets")
    .then (children) ->
      presets = []
      async.each(children, (appId, done) ->
        ZookeeperHandler.getData("modules/#{moduleName}/presets/#{appId}")
        .then (data) ->
          presets.push(data)
        .catch (error) ->
          logger.error("Error \"" + error + "\"", error.stack)
        .finally ->
          done()
      , ->
        deferred.resolve(presets)
      )
    .catch (error) ->
      logger.error(error, error.stack)
    deferred.promise

  @getAllOfModule: (moduleName) ->
    deferred = Q.defer()
    unless Module.modules[moduleName]?
      deferred.reject("module #{moduleName} not active or unknown")
    else
      deferred.resolve(Module.modules[moduleName].presets)
    deferred.promise

  @cachePresets: ->
    deferred = Q.defer()
    modules = require("./Module").modules
    @getAllFromZookeeper()
    .then (modulepresets) ->
      count = 0
      for modulename, presets of modulepresets
        for preset in presets
          modules[modulename].createPreset(preset)
          count++
      deferred.resolve(count)
    .catch (error) ->
      deferred.reject(error)
    deferred.promise

module.exports = ModulePreset
