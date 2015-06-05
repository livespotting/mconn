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
  'ws'
  '$scope'
  (ws, $scope) ->
    #angular.element(document).ready ->
    $scope.numberOfJobs = 0
    'use strict'
    ws.on 'connect', ->
      ws.emit 'getJobs', initial: true
      ws.on 'gotMConnEnv', (mconnenv) ->
          $scope.mconnenv = mconnenv
          console.log mconnenv
      ws.on 'allJobs', (jobs) ->
        $scope.jobs = jobs
        totalJobsCount = if jobs.length then jobs.length else 0 # +1 for active element
        $scope.numberOfJobs = totalJobsCount
      ws.on 'updateJobTime', (time) ->
        $scope.jobtime = time
      ws.on 'removeActiveJob', (jobData) ->
        $scope.activeJob = null
    resetOld = ->
      $("#logging").hide() #hide logging overlay
      $(".navbar-nav li").removeClass("active")
    $scope.showQueue = ->
      resetOld()
      $(".navbar-nav li.queue").addClass("active")
    $scope.showLog = ->
      resetOld()
      $(".navbar-nav li.log").addClass("active")
      $("#logging").show()
      return
]

this.app.controller 'logsController', [
  'ws'
  '$scope'
  (ws, $scope) ->
    'use strict'
    ws.on 'connect', ->
      ws.emit "getLog"
]
