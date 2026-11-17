# `container-console-docker-ce` overview

## What it is

A local, in-browser console that manages the container environment of the Linux machine: it shows the state of docker-ce and manages containers, images, volumes, networks, Compose projects and the Kubernetes cluster of the kubeconfig. It runs as a Go service under `systemd --user` and opens from a desktop launcher. The screen is in English by default and in Brazilian Portuguese when the browser language starts with `pt`.

## Why

docker-ce has no user interface. The console offers management from a screen, without opening a terminal.

## Who uses it

One person, the owner of the machine, in the `docker` group. No login: it only accepts access from the machine itself (`127.0.0.1`), and it refuses `Host` and `Origin` headers of other sites. No roles, no other machines.

## What it does

| Area | Actions |
| --- | --- |
| Environment | Read-only: daemon state, version, CPUs, memory, storage driver, operating system and architecture. With the daemon off, it shows `sudo systemctl start docker` as text |
| Containers | List, start, stop, restart, remove, details, resource usage, live logs and terminal |
| Images | List, pull and remove |
| Volumes and networks | List, create, details and remove |
| Compose | List projects, up, stop and remove |
| Kubernetes | With the current kubeconfig context or `CONSOLE_KUBE_CONTEXT`: list and detail namespaces, pods, deployments and services; remove; scale deployments; live logs; terminal in the pod; apply YAML (invalid YAML is refused and nothing changes). Without a reachable cluster, it shows unavailable |
| Cleanup | Removes what no active container uses: stopped containers, unused images and networks, volumes only on request, and the build cache |

Rules that hold across the whole screen: removal always asks for confirmation; an action that fails shows the error as received, untranslated, and the list keeps showing the real state; with Docker off the screen opens, shows the state and keeps the Docker actions disabled, with the reason; a change must show up within 2 s, with up to 30 containers.

## What it does not do

Start or stop the Docker daemon, adjust its resources, create or start a Kubernetes cluster, measure performance, build images from the screen, use from other machines or by other users, and cloud.

## State

- The tool has no automated tests. It is verified by compiling (`make check`) and by the [manual tests](manual-tests.md), which you run in a real browser on this machine.
- The theme follows the operating system by default, and the person switches between system, dark and light in the side menu. The contrast was computed by script; the result on screen is checked in the [manual tests](manual-tests.md#theme).

## Map

[README](../README.md) · [architecture](architecture.md) · [API](api.md) · [operations](operations.md) · [manual tests](manual-tests.md)
