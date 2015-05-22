this.app.controller 'jobsController', [
  'ws'
  '$scope'
  (ws, $scope) ->
    #angular.element(document).ready ->
    $scope.numberOfJobs = 0
    'use strict'
    ws.on 'connect', ->
      ws.emit 'getJobs', initial: true
      ws.on 'allJobs', (jobs) ->
        $scope.jobs = jobs
        setTimeout ->
          $('.tooltip-top').tooltip({
            placement: 'top',
            viewport: {selector: 'body', padding: 2}
          })
          $('.tooltip-viewport-top').tooltip({
            placement: 'top',
            viewport: {selector: '.container-viewport', padding: 2}
          })
        ,250
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
