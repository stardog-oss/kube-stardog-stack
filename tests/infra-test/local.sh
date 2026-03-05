#!/bin/bash

minikube delete
minikube start --driver=docker --cpus=2 --memory=6144 --kubernetes-version=v1.29.4
cd ../../
tests/infra-test/smoke.sh 2>&1 | tee smoke.err
