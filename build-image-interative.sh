#export IMAGE="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888/rhoar-nodejs/nodejs-10:rhoar-nodejs-10-rhel-7-candidate-86971-20180511041439"
#export IMAGE="bucharestgold/centos7-s2i-nodejs:10.x"
#export IMAGE="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888/rhoar-nodejs/nodejs-10:rhoar-nodejs-10-rhel-7-candidate-11567-20180807053735"
#export IMAGE="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888/rhoar-nodejs/nodejs-10:rhoar-nodejs-10-rhel-7-containers-candidate-61054-20181001121746"
export IMAGE="nodeshift/ubi8-s2i-nodejs:12.x"
docker run -ti -v ${PWD}/test/test-app:/opt/app-root/src $IMAGE /bin/bash
