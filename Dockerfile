FROM node:0.12.4

RUN dpkg-reconfigure --frontend noninteractive tzdata

RUN npm install -g coffee-script coffeelint grunt-cli

WORKDIR /application
COPY . /application

RUN npm install

RUN grunt build

EXPOSE 1234

CMD ["npm", "start"]
