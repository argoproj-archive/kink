# kink (Kubernetes-in-kubernetes)

This repository has the source code for building docker image and an [argo](http://argoproj.io) workflow for running a kubernetes 
cluster inside another kubernetes cluster.

## Build (optional)

To build docker image do the following:

```
cd images
docker build .
```

## Run

- Download and install [argo](http://argoproj.io)
- Add this `https://github.com/abhinavdas/kink.git` repo to `Administration -> Integrations -> Source Code Management -> Git` (select public repository option)
- Click on a commit and select the `kubernetes-workflow`. 
- Options required are an `Application Name` and `Cluster Id`. Select a short `dns friendly` cluster Id and Application Name.
