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

moment = require("moment")
require("colors")

LEVEL_ERROR = 1
LEVEL_WARN = 2
LEVEL_INFO = 3
LEVEL_DEBUG = 4

# create logs on console
#
class Logger

  # constructor for MconnLogger with context
  #
  # @param [String] context context of class
  #
  constructor: (@context) -> @

  # is the logger muted?? (used in unit tests)
  #
  @isMuted: ->
    return process.env.LOGGER_MUTED

  # get the last 'items' items of the log
  #
  # @param [Number] How many log entries should be shown on gui
  #
  getCurrentLog: (items = 150) ->
    return Logger.log.slice(-1 * items)

  # log a message to console and to gui
  #
  # @param [String] Message
  # @param [String] Context of log (classname where the log occured)
  # @param [String] info, warn, err or debug
  # @param [String] color in console
  #
  logMessage: (message, context, type, color) ->
    if Logger.isMuted() then return
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
  info: (message, context = @context) ->
    if process.env.MCONN_LOGGER_LEVEL >= LEVEL_INFO
      @logMessage(message, context, "INFO", false)

  # log warning
  #
  # @param [String] Message
  # @param [String] Context of log (classname where the log occured)
  #
  warn: (message, context = @context) ->
    if process.env.MCONN_LOGGER_LEVEL >= LEVEL_WARN
      if process.env.NODE_ENV is "development"
        @logMessage(message, context, "WARN", "red")
      else
        @logMessage(message, context, "WARN", false)

  # log error
  #
  # @param [String] Message
  # @param [String] Context of log (classname where the log occured)
  #
  error: (message, stack, context = @context) ->
    if process.env.MCONN_LOGGER_LEsVEL >= LEVEL_ERROR
      if process.env.NODE_ENV is "development" or process.env.MCONN_LOGGER_LEVEL >= LEVEL_DEBUG
        @logMessage(message + stack, context, "ERROR", "red")
      else
        @logMessage(message, context, "ERROR", false)

  # log debug
  #
  # @param [String] Message
  # @param [String] Context of log (classname where the log occured)
  #
  debug: (type, message, context = @context, color = "yellow") ->
    if process.env.MCONN_LOGGER_LEVEL >= LEVEL_DEBUG
      @logMessage(message[color], context, "DEBUG", false)

# export new loggerinstance with context
#
# @param [String] context context of this logger
#
module.exports = (context) ->
  logger = new Logger(context)
  return logger
