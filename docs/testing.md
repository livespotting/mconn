# Testing

- [Enviroments-Variables](#enviroment-variables)
- [Examples for CI-Services](#examples-for-ci-services)

## Enviroment-Variables
#### LOGGER_MUTED
Enable or disable the console output of the ProcessManager

Default-Value:
`` false ``
#### MCONN_TEST_PATH
Like MCONN_PATH but just for testings

Default-Value:
```coffee
if process.env.MCONN_TEST_PATH then process.env.MCONN_TEST_PATH else "/mconn"
```

#### MCONN_TEST_MODULE_START
Like MCONN_MODULE_START but just for testings

Default-Value:
```coffee
process.env.MCONN_TEST_MODULE = if process.env.MCONN_TEST_MODULE then process.env.MCONN_TEST_MODULE  else "Test"
```

#### MCONN_TEST_MODULE_PATH
Like MCONN_MODULE_PATH but just for testings

Default-Value:
```coffee
if process.env.MCONN_TEST_MODULE_PATH then process.env.MCONN_TEST_MODULE_PATH else __dirname + "/testmodules"
```

#### NODE_MODE
"development" will us the uncompressed js-libs for the ui and "production" the minifyed versions. For frontend-development the uncompressed libs shows more debug information upon the console.

Default-Value:
`` production ``

## Examples for CI-Services
#### Travis-CI
```sh
language: node_js
node_js:
  - "0.12.7"
before_script:
  - wget http://apache.openmirror.de/zookeeper/zookeeper-3.4.6/zookeeper-3.4.6.tar.gz
  - tar xf zookeeper-3.4.6.tar.gz
  - cp zookeeper-3.4.6/conf/zoo_sample.cfg zookeeper-3.4.6/conf/zoo.cfg
  - chmod +x zookeeper-3.4.6/bin/zkServer.sh
  - mkdir -p /tmp/zookeeper
  - npm install -g coffee-script coffeelint grunt-cli bower mocha chai
script:
  - zookeeper-3.4.6/bin/zkServer.sh start
  - grunt build
  - grunt test-silent
```

#### Jenkins
We are using Jenkins-on-Mesos with the "Use Docker Containerizer"-Option. 

**Dockerfile for the Jenkins-Slave:**
```dockerfile
FROM node:0.12.7

RUN apt-get update && \
    apt-get install -y openjdk-7-jre-headless unzip apache2-utils zookeeperd

RUN npm install -g coffeelint codo coffee-script grunt grunt-cli grunt-coffeelint bower mocha chai coffee-coverage istanbul
```

**Jenkins-Settings:**
- Build
 - Execute Shell:
  ```sh
npm install
grunt build
```
 - Inject environment variables:
  ```sh
MCONN_PATH=/jenkins/workspace/mconn/
```
 - Execute Shell:
  ```sh
/usr/share/zookeeper/bin/zkServer.sh start
grunt test-xunit
grunt test-cov
```
- Post-build Actions
 - Publish JUnit test result report
   - Test report XMLs: `` build/xunit.xml ``
 - Publish Cobertura Coverage Report
   - Cobertura xml report pattern: `` coverage/cobertura-coverage.xml ``
 - Publish Checkstyle analysis results
   - Checkstyle results: ``build/checkstyle-result.xml ``
   
