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
        'lib/bootstrap/dist/css/bootstrap.css'
      ]
      js: [
        'lib/jquery/dist/jquery.js'
        'lib/bootstrap/dist/js/bootstrap.js'
        'lib/angular/angular.js'
        'lib/angular-route/angular-route.js'
      ]
    css: [ 'css/mconn.css' ]
    js: [
      'js/app.js'
      'js/controllers.js'
    ]
