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

this.app = angular.module('app', ['ngRoute'])

this.connectToNamespace = (namespace, $rootScope) ->
  console.info ("connect to namespace #{namespace}")
  if $rootScope.socket then $rootScope.socket.disconnect()
  $rootScope.socket = io.connect($(".master-url").data("masterurl") + "/" + namespace, {'forceNew': true, 'secure': true})
  {
  emit: (event, data, callback) ->
    $rootScope.socket .emit event, data, ->
      args = arguments
      $rootScope.$apply ->
        if callback
          callback.apply null, args
  on: (event, callback) ->
    $rootScope.socket .on event, ->
      args = arguments
      $rootScope.$apply ->
        callback.apply null, args
  once: (event, callback) ->
    $rootScope.socket .once event, ->
      args = arguments
      $rootScope.$apply ->
        callback.apply null, args
  off: (event, callback) ->
    $rootScope.socket .removeListener event, callback
  }
  $rootScope.socket.on 'allTasks', (tasks) ->
    $rootScope.$apply ->
      $rootScope.numberOfTasks = tasks.length
  return $rootScope.socket

this.app.config [
  '$routeProvider',
  ($routeProvider) ->
    $routeProvider.when('/queue',
      templateUrl: 'queue'
      controller: 'tasksController')
    .when('/',
      redirectTo: '/queue'
    )
]
