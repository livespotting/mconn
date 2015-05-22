FROM node:0.12

RUN dpkg-reconfigure --frontend noninteractive tzdata

RUN apt-get update && \
    apt-get install -y ant && \
    npm install -g coffee-script

WORKDIR /application
COPY . /application

RUN ant coffee-compile
RUN ant node-modules

EXPOSE 1234

CMD ["npm", "start"]
