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

this.app.controller 'jobsController', [
  '$scope'
  '$rootScope'
  ($scope, $rootScope) ->
    $rootScope.socket = window.connectToNamespace("home", $rootScope)
    $scope.numberOfJobs = 0
    'use strict'
    $rootScope.socket.on 'connect', ->
      $rootScope.socket.emit 'getJobs', initial: true
      $rootScope.socket.on 'gotMConnEnv', (mconnenv) ->
        console.log mconnenv
      $rootScope.socket.on 'allJobs', (jobs) ->
        $scope.$apply ->
          $scope.jobs = jobs
          totalJobsCount = if jobs.length then jobs.length else 0 # +1 for active element
          $rootScope.numberOfJobs = totalJobsCount
          console.log $rootScope.numberOfJobs
      $rootScope.socket.on 'updateJobTime', (time) ->
        $scope.jobtime = time
      $rootScope.socket.on 'removeActiveJob', (jobData) ->
        $scope.activeJob = null
      return
]

this.app.controller 'NavCtrl', ($scope, $location) ->
  $scope.isActive = (viewLocation) ->
    return viewLocation is $location.path()

  $scope.isActiveMainMenu = (viewLocation) ->
    partsVL = viewLocation.split("/")
    partsL = $location.path().split("/")
    if partsVL.length >= 3 # like /modules/HelloWorld
      return "/" + partsVL[1] + "/" + partsVL[2] is "/" + partsL[1] + "/" + partsL[2]
    else if partsVL.length >= 2
      return "/" + partsVL[1]  is "/" + partsL[1]

  $scope.classActive = (viewLocation) ->
    if( $scope.isActive(viewLocation) )
      return 'active'
    else
      return ''

  $scope.classActiveMainMenu = (viewLocation) ->
    if( $scope.isActiveMainMenu(viewLocation) )
      return 'active'
    else
      return ''
