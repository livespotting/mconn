coffeelint -f build/coffeelint.json --reporter checkstyle src/application > build/logs/checkstyle-result.xml
echo "created checkstyle file build/logs/checkstyle-result.xml"
