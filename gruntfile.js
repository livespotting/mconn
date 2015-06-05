'use strict';

module.exports = function(grunt) {
	// Unified Watch Object
	var watchFiles = {
		clientJS: ['bin/webserver/public/js/*.js'],
		clientCSS: ['bin/webserver/public/css/*.css']
	};

	// Project Configuration
	grunt.initConfig({
		pkg: grunt.file.readJSON('package.json'),
		watch: {
			clientJS: {
				files: watchFiles.clientJS,
				tasks: ['jshint'],
				options: {
					livereload: true
				}
			},
			clientCSS: {
				files: watchFiles.clientCSS,
				tasks: ['csslint'],
				options: {
					livereload: true
				}
			}
		},
		csslint: {
			options: {
				csslintrc: '.csslintrc'
			},
			all: {
				src: watchFiles.clientCSS
			}
		},
        coffeelint: {
            app: ['src/application/**/*.coffee'],
            options: {
                configFile: 'build/coffeelint.json',
                reporter: 'checkstyle'
            }
        },

		uglify: {
			production: {
				options: {
					mangle: true
				},
				files: {
					'bin/webserver/public/dist/application.min.js': 'bin/webserver/public/dist/application.js'
				}
			}
		},
		cssmin: {
			combine: {
				files: {
					'bin/webserver/public/dist/application.min.css': '<%= applicationCSSFiles %>'
				}
			}
		},
		ngAnnotate: {
			production: {
				files: {
					'bin/webserver/public/dist/application.js': '<%= applicationJavaScriptFiles %>'
				}
			}
		},
		env: {
			test: {
				NODE_ENV: 'test'
			},
			secure: {
				NODE_ENV: 'secure'
			}
		},
        shell: {
            clear:{
                command: 'rm -Rf bin/ && rm -Rf build/logs && mkdir build/logs && echo "removed bin/\nremoved build/logs\ncreated build/logs directory"'
            },
            executeCoffeelint: {
                command: 'build/coffeelint.sh'
            },
            compileCoffee: {
                command: 'coffee -o bin -c src/application && echo "compiled coffeescript files"'
            }
        },copy: {
            statics: {
                files: [
                    // includes files within path
                    {expand: true,cwd: 'static/webserver/', src: ['**'], dest: 'bin/webserver'}
                ]
            }
        }
	});

	// Load NPM tasks
	require('load-grunt-tasks')(grunt);
    grunt.loadNpmTasks('grunt-contrib-copy')

	// Making grunt default to force in order not to break the project.
	grunt.option('force', true);
    grunt.task.registerTask('loadConfig', 'Task that loads the config into a grunt option.', function() {

        grunt.config.set('applicationJavaScriptFiles', watchFiles.clientJS);
        grunt.config.set('applicationCSSFiles', watchFiles.clientCSS);
    });
	// Execute checkstyle file from coffeelint
	grunt.registerTask('checkstyle', ['shell:executeCoffeelint']);

    //Default task
	grunt.registerTask('default', ['lint', 'concurrent:default']);

	// Lint task(s).
	grunt.registerTask('lint', ['shell:clear','csslint', 'coffeelint', 'checkstyle']);

	// Build task(s).
	grunt.registerTask('build', ['shell:clear','loadConfig','lint', 'copy','shell:compileCoffee','ngAnnotate', 'uglify', 'cssmin']);


};
