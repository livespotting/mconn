#
# Based on https://www.npmjs.com/package/node-process-manager
# just modified to suppress logging information that breaks xunit testreport
#

child_process = require('child_process')
_ = require('underscore')
moment = require('moment')
# Based on http://blog.argteam.com/coding/hardening-node-js-for-production-part-3-zero-downtime-deployments-with-nginx/
module.exports = (script, env, killTimeoutMS) ->
  @script = script
  @env = env or {}
  @killTimeoutMS = killTimeoutMS or 60 * 1000
  # Colors to display in the console.
  colors =
    green: '[32m'
    red: '[31m'
    blue: '[35m'
    yellow: '[33m'
    darkblue: '[34m'
    grey: '[90m'
    reset: '[0m'

  @intro = ->
    colors.grey + moment().format('YYYY-MM-DD HH:mm:ss') + colors.reset + (if @env.name then ' [' + colors.blue +
      @env.name + colors.reset + '] ' else if @pid then ' [' + colors.blue + @pid + colors.reset + '] ' else ' ')

  # This method spawns or respawns our process, and monitors stdout, sterr and makes sure its running
  #
  @_spawn = ->
    # This variable indicates whether the process should be running or exiting.
    # If the process exit unexpectantly, we'll restart it.
    @exiting = false
    @killCallbacks = []
    # process.execPath ... path to node... i.e. /usr/local/Cellar/node/0.10.12/bin/node
    @child = child_process.spawn(process.execPath, [ script ], env: _.extend(process.env, @env))
    @pid = @child.pid
    # Lets relay the console logs.
    @child.stdout.on 'data', ((buf) ->
      # @todo consider logging each service
      if process.env.MCONN_TEST_SHOW_APP_LOGS then process.stdout.write(this.intro() + buf)
      return
    ).bind(this)
    # Lets relay the error logs.
    @child.stderr.on 'data', ((buf) ->
      # @todo consider logging each service
      if process.env.MCONN_TEST_SHOW_APP_LOGS then process.stderr.write(this.intro() + buf)
      return
    ).bind(this)
    # Lets respawn the process unless we are in exit mode.
    @child.on 'exit', ((code, signal) ->
      clearTimeout @killTimeout
      @child = null
      # If this was an unexpected exit lets respawn.
      if !@exiting
        @_spawn()
      @pid = null
      # Lets not get in a loop here.
      funcs = @killCallbacks
      @killCallbacks = []
      funcs.forEach (f) ->
        if typeof f == 'function'
          f()
        return
      return
    ).bind(this)
    this

  # This method will restart the process.
  #
  @respawn = ->
    # If a child exists, lets first kill it before creating another.
    if @child
      @kill @_spawn.bind(this)
    else
      @_spawn()
    return

  # This method will stop the process from running.
  #
  @kill = (func) ->
    # Lets keep track of our callbacks and run each and every one of them.
    @killCallbacks.push func
    # Lets try to kill this process once.
    if !@exiting
      @exiting = true
      # If no argument is given, the process will be sent 'SIGTERM'
      @child.kill()
      # Lets give it 60 seconds, then lets kill it.
      @killTimeout = setTimeout((->
        @child.kill 'SIGKILL'
        @child = null
        # Lets not get in a loop here.
        funcs = @killCallbacks
        @killCallbacks = []
        funcs.forEach (f) ->
          if typeof f == 'function'
            f()
          return
        return
      ).bind(this), @killTimeoutMS)
    return

  # Lets start by spawning this process.
  @_spawn()
  this
