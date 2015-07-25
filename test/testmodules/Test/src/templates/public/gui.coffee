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

this.app.config [
  '$routeProvider',
  ($routeProvider) ->
    $routeProvider.when('/modules/Test/main',
      templateUrl: 'modules/Test/main'
      controller: 'TestCtrl')
    $routeProvider.when('/modules/Test/presets',
      templateUrl: 'modules/Test/presets'
      controller: 'TestCtrl')
    $routeProvider.when('/modules/Test/queue',
      templateUrl: 'modules/Test/queue'
      controller: 'TestCtrl')
]

this.app.controller 'TestCtrl', [
  '$scope'
  '$rootScope'
  ($scope, $rootScope) ->
    unless $scope.webSocketEventsAreBinded
        if $rootScope.socket then $rootScope.socket.disconnect()
        $rootScope.socket = window.connectToNamespace("Test", $rootScope)
        $rootScope.socket.on "updateTest", (data) ->
          $scope.$apply ->
            $scope.Testdata = data
        $rootScope.socket.on "updateTestInventory", (data) ->
          $scope.$apply ->
            $scope.inventory = data
        $rootScope.socket.on "updatePresets", (data) ->
          $scope.$apply ->
            $scope.presets = data
        $rootScope.socket.on "updateTestQueue", (data) ->
            $scope.$apply ->
              $scope.queue = data.queue
              $scope.queuelength = data.queuelength
        $scope.webSocketEventsAreBinded = true
]
