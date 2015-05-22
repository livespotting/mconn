moment = require("moment")
require("colors")

# create logs on console
#
class MConnLogger

  # constructor for MconnLogger with context
  #
  # @param [String] context context of class
  #
  constructor: (@context) -> @

  # is the logger muted?? (used in unit tests)
  #
  @isMuted: ->
    process.env.LOGGER_MUTED

  # get the last 'items' items of the log
  #
  # @param [Number] How many log entries should be shown on gui
  #
  getCurrentLog: (items = 150) ->
    return MConnLogger.log.slice(-1 * items)

  # log a message to console and to gui
  #
  # @param [String] Message
  # @param [String] Context of log (classname where the log occured)
  # @param [String] info, warn, err or debug
  # @param [String] color in console
  #
  logMessage: (message, context, type, color) ->
    if MConnLogger.isMuted() then return
    str =  "[#{moment().format('DD-MM-YYYY HH:mm:ss')}] [#{type}] #{message} (#{context})"

    # print on console
    unless color
      console.log(str)
    else
      console.log(str[color])

  # log info
  #
  # @param [String] Message
  # @param [String] Context of log (classname where the log occured)
  #
  logInfo: (message, context = @context) ->
    @logMessage(message, context, "INFO", false)

  # log warning
  #
  # @param [String] Message
  # @param [String] Context of log (classname where the log occured)
  #
  logWarn: (message, context = @context) ->
    @logMessage(message, context, "WARN", false)

  # log error
  #
  # @param [String] Message
  # @param [String] Context of log (classname where the log occured)
  #
  logError: (message, context = @context) ->
    @logMessage(message, context, "ERROR", false)

  # log debug
  #
  # @param [String] Message
  # @param [String] Context of log (classname where the log occured)
  #
  debug: (type, message, context = @context, color = "yellow") ->
    if process.env.MCONN_DEBUG is "true"
      @logMessage(message[color], context, type, false)

# export new loggerinstance with context
#
# @param [String] context context of this logger
#
module.exports = (context) ->
  logger = new MConnLogger(context)
  return logger
