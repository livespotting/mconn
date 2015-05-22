this.app = angular.module('app', [])

this.app.factory 'ws', [
  '$rootScope'
  ($rootScope) ->
    #angular.element(document).ready ->
    console.log $(".master-url").data("masterurl")
    socket = io.connect($(".master-url").data("masterurl"))
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
    off: (event, callback) ->
      socket.removeListener event, callback
    }
]
