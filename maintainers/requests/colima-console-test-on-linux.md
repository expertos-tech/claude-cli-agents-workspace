# Functional request: test the Colima console on a Linux machine

**Project:** claude-cli-agents-workspace

**State:** idea. Size: feature. Source: the owner (2026-11-18), after `accordion-motion`.

## 1. Objective

`tools/container-console-colima` is built for macOS, and its maintainers work on Linux with docker-ce. Today its screens
can be checked on Linux only against docker-ce (`CONSOLE_DOCKER_HOST=unix:///var/run/docker.sock`), which covers the
container, Compose and Kubernetes screens but never the Colima ones: its state, start, stop and profile. The goal is a
documented, repeatable way to run a real Colima next to docker-ce on Linux, to test that console end to end without a
Mac, and without disturbing the docker-ce the machine already uses.

What was found (2026-11-18): Colima runs on Linux through Lima and QEMU with KVM; a Linux machine with `/dev/kvm`,
hardware virtualization and `qemu-system-x86_64` needs only the `colima` and `limactl` binaries. Running Colima inside
a docker-ce container is possible (`--privileged`, `/dev/kvm`) but nests a VM in a container, exposes its socket and
ports through two layers, and leaves the console calling a `colima` it cannot reach; it is not recommended.

## 3. Business rules

- BR-1: Colima runs natively on the Linux machine (Lima and QEMU with KVM), never inside a container.
- BR-2: The docker-ce of the machine is untouched: the current `docker` context stays the default one after Colima
  starts and stops (to verify: `colima start --activate=false`, or `docker context use default` right after), and no
  container, image, volume or network of docker-ce changes.
- BR-3: The Colima VM uses a profile of its own (for example `caw-test`) with the smallest resources the console needs,
  and is deleted (`colima delete`) at the end of a test.
- BR-4: The Colima console runs by hand on Linux (`make build`, then the binary with `CONSOLE_LISTEN`,
  `CONSOLE_STATE_DIR` and `CONSOLE_LOG_FILE` under a temporary folder), since its installer is for macOS (launchd);
  nothing is installed as a service.
- BR-5: Ports: the console on its own port (17850 by default, never 27850, which is the docker-ce console's); a port a
  Colima container publishes that docker-ce already uses is refused by Colima, not by the console.
- BR-6: The way to do it is written for maintainers (decision D-2 says where), with the prerequisites check, the
  steps, the cleanup and what it does not cover (launchd, the Dock icon, macOS paths).

## 4. Acceptance criteria

- AC-1: Given a Linux machine with KVM and docker-ce, when the steps run, then `colima status -p <profile>` reports
  running, and `docker context show` still prints `default`.
- AC-2: Given the Colima console running by hand against that profile, when its environment screen opens, then it
  shows the real Colima state, and start and stop from the screen change it.
- AC-3: Given the test over, when the cleanup runs, then the profile is gone, docker-ce lists the same containers,
  images, volumes and networks as before, and no service or launcher was installed.
- AC-4: Given a machine without `/dev/kvm` or without permission on it, when the prerequisites check runs, then it
  says what is missing and changes nothing.

## 7. Out of scope

- Colima inside a docker-ce container.
- Offering both consoles in `/run-tools` on one machine (its RN-4 shows one console per machine).
- A Linux installer for the Colima console.
- Changing the Colima console's code: a defect found while testing becomes its own request.

## Decisions for the owner

- D-1: Worth doing, or test the Colima console on a Mac at each change to it? (Recommended: do it; the maintainers
  work on Linux.)
- D-2: Where it lives: a section of `tools/container-console-colima/docs/` (created by `import-from-fork` BR-11), a
  maintenance script in `tests/` that runs the check, the start and the cleanup, or both. (Recommended: the doc first;
  a script only if it is run often.)
- D-3: How the `colima` and `limactl` binaries reach the machine: the official releases, pinned to a version and
  checked by checksum, or a package manager. (Recommended: pinned releases.)

## 11. Steps and effort

| Step | Effort | Why |
| --- | --- | --- |
| 1. Prove BR-2 and BR-3 on a machine: install the pinned binaries, start a profile without switching the context, delete it | medium | It touches the machine's Docker setup |
| 2. Run the Colima console against it and walk its environment screen (AC-2) | medium | First run of that screen on Linux |
| 3. Write the doc (and the script, per D-2) with the check, the steps and the cleanup | low | Documentation of a proven run |
