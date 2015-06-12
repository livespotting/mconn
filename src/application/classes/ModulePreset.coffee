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
          logger.error("Error reading preset " + error.toString())
        .finally -> done()
      , ->
        deferred.resolve(fileContents)
      )
    deferred.promise

  # read available presets from zookeeper
  #
  # @return [Promise] resolves with list of presets
  #
  @readConfigsFromZookeeper: ->
    return ZookeeperHandler.getChildren("presets")

  # determines diff between return of presetSourceMethod and current zookeeper storage and
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
          logger.error("Create error \"" + error + "\"")
        .finally ->
          done()
      , ->
        deferred.resolve(pushToZookeeper)
      )
    .catch (error) ->
      logger.error("Create error \"" + error.toString() + " " + error.stack + "\"")
      deferred.reject(error)
    deferred.promise

  # syncs difference between presetSourceMethod and current zk storage on zk storage
  #
  # @param [Function] presetSourceMethod has to be a promise returning method, that resolves with an array
  # of the presets [{appId: dev-app-1, options:{}...},{appId: dev-app-2 ...]
  #
  # @return [Number] number of written preset
  #
  @sync: (presetSourceMethod, allwaysUpdate = false) ->
    deferred = Q.defer()
    @diff(presetSourceMethod, allwaysUpdate)
    .then (result) ->
      count = 0
      async.each(result,
        (preset, done) ->
          clearedAppName = preset.appId.split("/")[1]
          Module = require("./Module")
          unless Module.isEnabled(preset.moduleName)
            promise = Q.reject("Module \"#{preset.moduleName}\" is not enabled - skipping preset for app \"#{clearedAppName}\"")
          else
            if preset.lastEdit
              logger.info("Forward preset update \"#{clearedAppName}\" for module \"#{preset.moduleName}\" to
                ZookeeperHandler")
              promise = ZookeeperHandler.setData("modules/#{preset.moduleName}/presets/#{clearedAppName}",preset)
            else
              logger.info("Forward preset creation \"#{clearedAppName}\" for module \"#{preset.moduleName}\" to
                ZookeeperHandler")
              promise = ZookeeperHandler.createNode("modules/#{preset.moduleName}/presets/#{clearedAppName}",
                new Buffer(JSON.stringify(preset)), zookeeper.ACL.OPEN, zookeeper.CreateMode.PERSISTENT)
          promise
          .then ->
            Module.modules[preset.moduleName].updatePresetsOnGui()
            count++
          .catch (error) ->
            logger.error(error)
          .finally ->
            done()
        , ->
          deferred.resolve(count)
      )
    deferred.promise

  # removes presets from zookeeper
  #
  # @param [Array] presets array of presets
  #
  # @return [Promise] resolves with nothing
  #
  @remove: (presets) ->
    deferred = Q.defer()
    async.each(presets,
      (preset, done) ->
        clearedAppName = preset.appId.split("/")[1]
        logger.warn("Remove preset \"" + preset.appId + "\" for module \"#{preset.moduleName}\"")
        ZookeeperHandler.remove("modules/#{preset.moduleName}/presets/#{clearedAppName}")
        .catch (error) ->
          logger.error("Error removing node \"" + clearedAppName + "\" \"" + error.toString(), "\"")
        .finally ->
          done()
      , ->
        deferred.resolve()
    )
    deferred.promise

  # get all presets of all modules
  #
  # @return [Promise] resolves with presets
  #
  @getAll: ->
    deferred = Q.defer()
    modules = require("../classes/Module").modules
    presets = {}
    modulenames = []
    for modulename, module of modules
      modulenames.push(modulename)
    async.each(modulenames,
      (module, done) =>
        @getAllOfModule(module).then (modulepresets) ->
          presets[module] = modulepresets
          done()
    ,
      ->
        deferred.resolve(presets)
    )
    deferred.promise

  # get all presets of a given module
  #
  # @param [String] moduleName
  #
  # @return [Promise]
  #
  @getAllOfModule: (moduleName) ->
    deferred = Q.defer()
    ZookeeperHandler.getChildren("modules/#{moduleName}/presets")
    .then (children) ->
      presets = []
      async.each(children, (appId, done) ->
        ZookeeperHandler.getData("modules/#{moduleName}/presets/#{appId}")
        .then (data) ->
          presets.push(data)
        .catch (error) ->
          logger.error("Error \"" + error + "\"")
        .finally ->
          done()
      , ->
        deferred.resolve(presets)
      )
    deferred.promise

module.exports = ModulePreset
