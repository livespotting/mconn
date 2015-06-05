### Changes from 0.0.5 to 0.0.6

* update to Node 0.12.4
* update NPM dependencies
* update frontend libs (angular, bootstrap, ..)
* first code cleanup
  * you have to clean up the mconn-node on zookeeper!!!
* switch Ant to Grunt
  * move static webserver files (templates, libs, css) to folder static/
  * minify frontend jscript for productive (default) usage
  * minify cssfiles
  * use jscript maps for productive (default) usages
  * add leverage browser-caching for all assets 
  * remove bin folder from repo (bin folder is now being created by executing ‚grunt build‘)
* render jade-templates
  * reduces pageload from ~600ms up to ~8ms
* POST to exit leader or node
