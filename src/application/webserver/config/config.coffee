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

_ = require('lodash')

process.env.NODE_ENV  = if process.env.NODE_ENV then process.env.NODE_ENV else "production"

files = _.extend(
  require('./env/all')
  require('./env/' + process.env.NODE_ENV) || {}
)

module.exports.extraJavascriptFiles = []

module.exports.getJavascriptFiles = =>
  js = []
  for file in files.assets.lib.js
    js.push(file)
  for file in files.assets.js
    js.push(file)
  for file in @extraJavascriptFiles
    js.push(file)
  return js

module.exports.getCssFiles = ->
  css = []
  for file in files.assets.lib.css
    css.push(file)
  for file in files.assets.css
    css.push(file)
  return css
