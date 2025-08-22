FROM python:latest
WORKDIR /usr/app/src
COPY helloworld.py ./
CMD [ "python", "./helloworld.py"]
