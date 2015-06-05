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

this.app = angular.module('app', [])

this.app.factory 'ws', [
  '$rootScope'
  ($rootScope) ->
    socket = io.connect($(".master-url").data("masterurl") + "/" + $(".modulename").data("modulename"))
    {
    emit: (event, data, callback) ->
      socket.emit event, data, ->
        args = arguments
        $rootScope.$apply ->
          if callback
            callback.apply null, args
    on: (event, callback) ->
      socket.on event, ->
        args = arguments
        $rootScope.$apply ->
          callback.apply null, args
    once: (event, callback) ->
        socket.once event, ->
            args = arguments
            $rootScope.$apply ->
                callback.apply null, args
    off: (event, callback) ->
      socket.removeListener event, callback
    }
]
