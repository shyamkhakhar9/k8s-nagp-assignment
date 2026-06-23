# README

Code Repo Link - https://github.com/shyamkhakhar9/k8s-nagp-assignment

Dockerhub URL - 730335193392.dkr.ecr.us-east-2.amazonaws.com

Documentation link - https://github.com/shyamkhakhar9/k8s-nagp-assignment/blob/main/DOCUMENTATION.md

## What is implemented?

- Go through Documentation link and it has complete details on what is setup and how everything is setup.

- I have created scripts for everything
    - pushing image to registry
    - creating secret for app
    - deploying the complete resource in kubernetes cluster including the load balancer
    - destroying the complete infra
    - scaling script to test hpa
    - rolling update strategy for api script
    - self healing testing

- Architecture - https://github.com/shyamkhakhar9/k8s-nagp-assignment/blob/main/DOCUMENTATION.md#31-architecture

- Here is the script path where I've mentioned what each script does - https://github.com/shyamkhakhar9/k8s-nagp-assignment/blob/main/DOCUMENTATION.md#35-automation-scripts

## Notes

- Currently for ingress I've configured port 80 only. But in actual we will have a ACM certificate created and then use port 443 in ingress. A DNS entry would have been done and the application will be accessible on custom domain.