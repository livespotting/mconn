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

module.exports =
  assets:
    lib:
      css: [
        'lib/bootstrap/dist/css/bootstrap.min.css'
      ]
      js: [
        'lib/jquery/dist/jquery.min.js'
        'lib/bootstrap/dist/js/bootstrap.min.js'
        'lib/angular/angular.min.js'
        'lib/angular-route/angular-route.min.js'
        'lib/moment/min/moment.min.js'
      ]
    css: [ 'dist/application.min.css' ]
    js: [ 'dist/application.min.js']
