'use strict'

module.exports = (grunt) ->
# Unified Watch Object
  watchFiles =
    clientJS: [ 'bin/webserver/public/js/*.js' ]
    clientCoffeeScript: [ 'src/**/*.coffee' ]
    clientCSS: [ 'bin/webserver/public/css/*.css' ]
  # Project Configuration
  grunt.initConfig
    pkg: grunt.file.readJSON('package.json')
    watch:
      clientCoffeeScript:
        files: watchFiles.clientCoffeeScript
        tasks: [
          'loadConfig'
          'lint'
          'copy'
          'shell:compileCoffee'
          'ngAnnotate'
          'uglify'
        ]
        options: livereload: true
      clientCSS:
        files: watchFiles.clientCSS
        tasks: [ 'cssmin' ]
        options: livereload: true
    csslint:
      options: csslintrc: '.csslintrc'
      all: src: watchFiles.clientCSS
    coffeelint:
      app: [ 'src/application/**/*.coffee' ]
      options:
        configFile: 'build/coffeelint.json'
        reporter: 'checkstyle'
    uglify: production:
      options: mangle: true
      files: 'bin/webserver/public/dist/application.min.js': 'bin/webserver/public/dist/application.js'
    cssmin: combine: files: 'bin/webserver/public/dist/application.min.css': '<%= applicationCSSFiles %>'
    ngAnnotate: production: files: 'bin/webserver/public/dist/application.js': '<%= applicationJavaScriptFiles %>'
    env:
      development: NODE_ENV: 'development'
      production: NODE_ENV: 'production'
    nodemon: dev:
      script: 'bin/start.js'
      options:
        nodeArgs: [ '--debug' ]
        ext: 'js,jade'
        watch: [ 'bin/' ]
        delay: 2500
    concurrent:
      default: [
        'watch'
        'nodemon'
      ]
      debug: [
        'nodemon'
        'watch'
        'node-inspector'
      ]
      options:
        logConcurrentOutput: true
        limit: 10
    shell:
      clear: command: 'rm -Rf bin/ && rm -Rf build/logs && mkdir build/logs && echo "removed bin/\nremoved build/logs\ncreated build/logs directory"'
      executeCoffeelint: command: 'build/coffeelint.sh'
      compileCoffee: command: 'coffee -o bin -c src/application && echo "compiled coffeescript files"'
      start: command: 'npm start'
      mocha_tests: command: 'mocha --compilers coffee:coffee-script/register -R xunit > xunit.xml'
      mocha_tests_cli: command: 'mocha --compilers coffee:coffee-script/register'
    copy: statics: files: [ {
      expand: true
      cwd: 'static/webserver/'
      src: [ '**' ]
      dest: 'bin/webserver'
    } ]
  # Load NPM tasks
  require('load-grunt-tasks') grunt
  grunt.loadNpmTasks 'grunt-contrib-copy'
  grunt.loadNpmTasks 'grunt-contrib-watch'
  grunt.loadNpmTasks 'grunt-concurrent'
  grunt.loadNpmTasks 'grunt-nodemon'
  # Making grunt default to force in order not to break the project.
  grunt.option 'force', true
  grunt.task.registerTask 'loadConfig', 'Task that loads the config into a grunt option.', ->
    grunt.config.set 'applicationJavaScriptFiles', watchFiles.clientJS
    grunt.config.set 'applicationCSSFiles', watchFiles.clientCSS
    return
  # Execute checkstyle file from coffeelint
  grunt.registerTask 'checkstyle', [ 'shell:executeCoffeelint' ]
  # Default task
  grunt.registerTask 'default', [
    'shell:clear'
    'loadConfig'
    'lint'
    'copy'
    'shell:compileCoffee'
    'ngAnnotate'
    'uglify'
    'cssmin'
    'concurrent:default'
  ]
  # Lint task(s).
  grunt.registerTask 'lint', [
    'shell:clear'
    'csslint'
    'coffeelint'
    'checkstyle'
  ]
  # Build task(s).
  grunt.registerTask 'build', [
    'shell:clear'
    'loadConfig'
    'lint'
    'copy'
    'shell:compileCoffee'
    'ngAnnotate'
    'uglify'
    'cssmin'
  ]
  # Test task(s).
  grunt.registerTask 'test', [
    'build'
    'shell:mocha_tests'
  ]
  grunt.registerTask 'test-cli', [
    'build'
    'shell:mocha_tests_cli'
  ]
  return
