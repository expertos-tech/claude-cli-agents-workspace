# `container-console-docker-ce` manual tests

- [How to use](#how-to-use)
- [Coverage](#coverage)
- [Preparation](#preparation)
- [Linux: installation, launcher and unit](#linux-installation-launcher-and-unit)
- [Machine restart](#machine-restart)
- [Local-only access](#local-only-access)
- [Environment off](#environment-off)
- [Read-only environment](#read-only-environment)
- [Daemon control outside the API](#daemon-control-outside-the-api)
- [Containers](#containers)
- [Images, volumes, networks and Compose](#images-volumes-networks-and-compose)
- [Kubernetes](#kubernetes)
- [Invalid YAML](#invalid-yaml)
- [Cancelling a removal](#cancelling-a-removal)
- [Error received and real state](#error-received-and-real-state)
- [Change within 2 s](#change-within-2-s)
- [Layout and identity](#layout-and-identity)
- [Theme](#theme)
- [Language](#language)

Verification guide, run by you, in a real browser and on this machine. The tool has no automated tests: it is verified by compiling (`make check`) and by these steps. Any item can fail: write down what you saw and bring it back.

## How to use

- Each block has numbered steps and the expected result. An item passes only if the result is the one described.
- Go in this order: preparation, Linux, environment off, read-only environment and the rest. The screens depend on Docker being on, except the environment-off block.
- The test resources carry the `cc-` prefix so you can clean them up at the end. Do not use the Grafana stack (`observability`) for testing: it receives the real telemetry.
- The UI labels quoted below are the English ones. A browser whose language starts with `pt` shows the screen in Brazilian Portuguese.

## Coverage

The requirements of the screen and of the installation:

| Requirement | Where to check |
| --- | --- |
| Daemon state and data, read-only | [Read-only environment](#read-only-environment) |
| The console does not control the daemon | [Daemon control outside the API](#daemon-control-outside-the-api) |
| Containers, live logs and terminal | [Containers](#containers) |
| Compose groups open and close with motion; the chevron of the jobs panel rotates | [Compose groups](#compose-groups) |
| Images, volumes, networks and Compose | [Images, volumes, networks and Compose](#images-volumes-networks-and-compose) |
| Kubernetes, logs and terminal in the pod | [Kubernetes](#kubernetes) |
| Invalid YAML changes nothing | [Invalid YAML](#invalid-yaml) |
| Cancelling a removal sends nothing | [Cancelling a removal](#cancelling-a-removal) |
| The screen works with Docker off | [Environment off](#environment-off) |
| Service and Grafana after login | [Linux](#linux-installation-launcher-and-unit) (service at login) and [machine restart](#machine-restart) |
| Access only from this machine | [Local-only access](#local-only-access) |
| Error received and real state | [Error received and real state](#error-received-and-real-state) |
| Change within 2 s | [Change within 2 s](#change-within-2-s) |
| Desktop launcher | [Linux](#linux-installation-launcher-and-unit) |
| Visual identity (`rules/frontend.md`) | [Layout and identity](#layout-and-identity) |
| Theme that follows the system, with the user's choice | [Theme](#theme) |
| English by default, Brazilian Portuguese for `pt` browsers | [Language](#language) |

## Preparation

1. In `tools/container-console-docker-ce`, with Node 24 on `PATH`: `make install`. This also installs the unit and the launcher, which the Linux tests check.
2. Without the unit, to test only the screen: `make build`, run `.data/bin/container-console-docker-ce` and open <http://127.0.0.1:27850/>. With the unit installed, just open the address.
3. With Docker on, create the test resources:
   - `docker run -d --name cc-test busybox sleep 3600`
   - A file `~/cc-test/compose.yaml`:

     ```yaml
     services:
       busybox:
         image: busybox
         command: ["sleep", "3600"]
     ```

4. The "Actions" panel sits below the content. It is where the progress, the success and the errors of every action show up.

## Linux: installation, launcher and unit

They cover the launcher, the unit and the service start at login. Run them in the `tools/container-console-docker-ce` folder, in your user's graphical session.

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | `make install` | Prints `installed container-console-docker-ce.service and <launcher path>`. `Container Console` shows in the applications menu, with the Claude CLI Agents Workspace icon undistorted |
| 2 | `curl -s http://127.0.0.1:27850/healthz` | Answers `{"status":"ok"}` |
| 3 | Click the launcher | The default browser opens <http://127.0.0.1:27850/> |
| 4 | Run `make install` again | Finishes without error, with a single launcher in the menu |
| 5 | `systemctl --user stop container-console-docker-ce.service`, then click the launcher | The service starts again, and the screen opens |
| 6 | `systemctl --user kill --signal=SIGKILL container-console-docker-ce.service` | systemd starts the service again: `/healthz` answers in about 2 s |
| 7 | Log out and log in again | `/healthz` answers without you opening a terminal |
| 8 | `bash linux/uninstall-console.sh` | The launcher, the unit and the binary are gone. Docker, the containers and `~/.local/state/container-console-docker-ce` stay |

Reinstall with `make install` before the next blocks.

## Machine restart

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | Restart the machine and log in to the graphical session | `/healthz` answers within 1 minute, without you opening a terminal |
| 2 | Open <http://127.0.0.1:27850/> | "On" badge in the top bar |
| 3 | Open <http://localhost:3000> | Healthy Grafana on port 3000, without you starting anything |

## Local-only access

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | `hostname -I` (the first IP of the active network interface), then `curl --max-time 3 http://<ip>:27850/healthz` | Connection refused (curl exits with error 7). Without an active network, mark it as **not verified**, never as passed |
| 2 | `curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: attacker.example' http://127.0.0.1:27850/healthz` | `403` |
| 3 | `curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' -H 'Origin: http://attacker.example' -H 'Sec-Fetch-Site: cross-site' -d '{"confirm":false}' http://127.0.0.1:27850/api/volumes/cc-x/remove` | `403` (without the protection it would be `422`, because the confirmation is missing) |
| 4 | `curl -s -o /dev/null -w '%{http_code}\n' -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" http://127.0.0.1:27850/ws/live/docker` | `403`, because `Origin` is missing |
| 5 | Run `CONSOLE_LISTEN=0.0.0.0:27850 .data/bin/container-console-docker-ce` | Exits with the error `CONSOLE_LISTEN: host must be 127.0.0.1` |

## Environment off

Stop Docker with `sudo systemctl stop docker.socket docker.service`. Only `docker.service` is not enough: `docker.socket` reactivates the daemon on the console's next read.

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | Open `#/overview` | The page opens. "Off" badge in the top bar and on the card. A sentence explains what is unavailable. Docker counts say "Unavailable" |
| 2 | Open `#/environment` | The sentence says Docker is off, and `sudo systemctl start docker` shows as text. No button to start or stop. A "What is unavailable with Docker off" card with Docker and Compose |
| 3 | Open `#/containers`, `#/images`, `#/volumes`, `#/networks` | A notice explains the reason, with a link to the environment. Create and pull fields and buttons show disabled, not hidden |
| 4 | Open `#/compose` | Known projects stay in the list, with the "Unknown" state. Start, Stop and Remove disabled. Adding a file stays enabled |
| 5 | With a reachable cluster, open `#/kubernetes` | The list keeps working: Kubernetes does not depend on the Docker state in this console |
| 6 | Run `sudo systemctl start docker` in the terminal | Without reloading, the badge turns to "On" and the lists come back |

## Read-only environment

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | With Docker on, open `#/environment` | "On" badge, with version, CPUs, memory, storage driver, operating system and architecture equal to those of `docker info` |
| 2 | Look for actions on the screen | There is no button, field or dialog: the screen only shows |
| 3 | Open `#/overview` | "Docker" card with state, version, CPUs and memory, and the "See the environment" link |
| 4 | Run the service with `CONSOLE_DOCKER_HOST` pointing to a socket you cannot read | "Unknown" badge, with the error received on the screen |

## Daemon control outside the API

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | `curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:27850/api/environment/start`; repeat with `stop`, `resources`, `kubernetes/start` and `kubernetes/stop` | `404` for all |
| 2 | Open `#/kubernetes` | There is no button to start or stop Kubernetes |

## Containers

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | Open `#/containers` | `cc-test` shows, with a state badge (icon and text). Pod containers do not show |
| 2 | On the row, click "Stop" | Job in the panel. The badge only changes when the real state changes: "Stopped" |
| 3 | Click "Start", then "Restart" | The state follows each action, back to "Running" |
| 4 | Click the container name | The details open, with full id, image, command, networks and mounts. "See all details as JSON" opens the inspect |
| 5 | Look at "Resource usage" | CPU, memory, network, disk and processes change every 2 s. When you leave the screen, the `/stats` queries stop (browser Network tab) |
| 6 | "Logs" tab, with `docker run -d --name cc-log busybox sh -c 'while true; do date; sleep 1; done'` | New lines show live, with no staircase in the margin. Tab leaves the log area |
| 7 | "Terminal" tab of `cc-test`; run `echo hello` and `ls` | The command runs inside the container. Resizing the window adjusts the terminal (`stty size` changes) |
| 8 | In the terminal, paste a text larger than 64 KiB | The connection does not drop and the whole text reaches the shell |
| 9 | In the terminal, press Shift+Esc and then Tab | The focus leaves the terminal and moves to the next control |
| 10 | Run `exit` | The badge shows the process ended with the code received. "Connect again" opens another shell |
| 11 | On "Remove", read the dialog and confirm | The dialog mentions `docker rm --force`. The container leaves the list |
| 12 | Run `docker tag busybox example.local/a/very/long/image/name/for/testing:1` and `docker run -d --name cc-long example.local/a/very/long/image/name/for/testing:1 sleep 600`; in `#/containers`, hover over the Image column | The name ends in `...` on a single line, and the browser shows the whole name next to the pointer. In the container details the name shows in full |

## Compose groups

With `docker run -d --name cc-a1 --label com.docker.compose.project=cc-group busybox sleep 600` and the same for `cc-a2`, in `#/containers`:

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | Click the `cc-group` toggle | In about 200 ms the chevron turns from pointing right to pointing down, and the two rows grow in height while they fade in. The rows below the group slide down without a jump |
| 2 | Click it again | The chevron turns back, the rows shrink to no height while they fade out, and the rows below slide up without a jump |
| 3 | With the group closed, press Tab through the table; open the accessibility tree (DevTools) | The focus never lands on `cc-a1` or `cc-a2`, and the tree shows neither. With the group open, their links and buttons take the focus |
| 4 | Open the group and reload the page | The group shows open at once, with no animation |
| 5 | Close the group and type `cc-a1` in the filter, then clear it | The group opens at once with the toggle disabled, and closes at once when the filter is cleared |
| 6 | With the group open, run `docker run -d --name cc-a3 --label com.docker.compose.project=cc-group busybox sleep 600`, then `docker rm -f cc-a3` | The row appears and then vanishes at once; the other rows do not animate |
| 7 | Repeat 1 and 2 with the table under 34 rem wide (a 390 px window) and between 34 and 60 rem (a 768 px window) | The same as 1 and 2, with the rows as blocks or with the stacked columns |
| 8 | With a job in the panel at the bottom, click "Collapse" and "Expand" | The chevron of the button turns by 180° each time |
| 9 | Turn "Animations" off in the menu, or the system's reduced motion on, and repeat 1, 2 and 8 | The group and the panel change at once, with no transition |

Cleanup: `docker rm -f cc-a1 cc-a2`.

## Images, volumes, networks and Compose

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | In `#/images`, pull `alpine:3.20` | Progress lines in the Actions panel. The image shows in the list when it finishes |
| 2 | Type `-rf` in the reference and click "Pull" | Format error below the field. Nothing is sent |
| 3 | Remove `alpine:3.20` | Dialog, then the image is gone |
| 4 | Remove the image of an existing container | The Docker error shows in the panel, and the image stays in the list |
| 5 | In `#/volumes`, create `cc-volume`, open the details and remove it | It shows, the inspect JSON opens, and it is gone after confirming |
| 6 | In `#/networks`, create `cc-network`, open the details and remove it | Same as the volume |
| 7 | Remove the `bridge` network | The Docker error shows, and the network stays in the list |
| 8 | In `#/compose`, click "Choose file" and pick `~/cc-test/compose.yaml` | The `zenity` dialog opens, filtering YAML. The project shows in the list |
| 9 | Click the button again and cancel in the dialog | Nothing changes, no error |
| 10 | Type `/tmp/x.txt` in the path field | Format error below the field |
| 11 | Type `/etc/compose.yaml` | Refusal from the service, with the reason, in the Actions panel |
| 12 | Type the path of `~/cc-test/compose.yaml` and add it | Works the same as the dialog |
| 13 | Click "Start", then "Stop" | The state goes to "Running" and then to "Stopped" |
| 14 | Create a volume in the project, click "Remove" and confirm with the option unchecked | The project leaves the list, and the volume stays (`docker volume ls`) |
| 15 | Add it again, start it, remove it with "Also remove the volumes of the project, which deletes their data" checked | The volume is gone. Reopening the dialog shows the option unchecked |

## Kubernetes

It needs a reachable cluster in the current kubeconfig context or in `CONSOLE_KUBE_CONTEXT`. Prepare with `kubectl create deployment cc-web --image=nginx:alpine` and `kubectl expose deployment cc-web --port=80`.

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | Open the Namespaces, Pods, Deployments and Services tabs | Real tables, with the test resource. The namespace filter works |
| 2 | Open the details of each kind | List data and full JSON |
| 3 | In Deployments, click "Scale", enter 3 | The dialog opens with the current value. Then, "3 of 3 ready" |
| 4 | Enter 1001 | Error below the field. Nothing is sent |
| 5 | Open a pod, Logs tab | Live lines |
| 6 | Terminal tab; run `hostname` | Shows the pod name |
| 7 | Remove the pod | The dialog warns that the deployment creates another one. A new pod shows |
| 8 | Remove the service, the deployment and a test namespace | Each one is gone after confirming |
| 9 | Point the context to a cluster that is down (`CONSOLE_KUBE_CONTEXT`, or `kubectl config use-context`) and open the screen | Notice "No Kubernetes cluster answers", with the error received. "Apply YAML" tab with field and button disabled. The screen keeps trying |
| 10 | Go back to the context of the running cluster | The list comes back without reloading |

If `kubectl` says the context does not exist, the cause is the one described in [operations](operations.md#common-failures), not a defect of the screen.

## Invalid YAML

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | In "Apply YAML", click "Apply" with the field empty | "The YAML is empty." below the field |
| 2 | Paste a Deployment with a field that does not exist in `spec` | The job fails, with the `kubectl` error in the panel. The text stays in the field. Nothing changes in the cluster (`kubectl get`) |
| 3 | Paste a valid resource and an invalid one in the same file | Same failure, and the valid one is not created either |
| 4 | Paste a valid YAML | The resource shows in the list |

## Cancelling a removal

For container, image, volume, network, Compose project, namespace, pod, deployment and service:

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | Click "Remove" | The dialog opens with the focus on "Cancel" |
| 2 | Try to move the focus out of the dialog with Tab | The focus does not leave it |
| 3 | Click "Cancel" | The dialog closes, the focus goes back to the button and the resource stays. In the Network tab, no POST |
| 4 | Repeat and press Esc | Same result |

## Error received and real state

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | In another terminal, `docker rm -f cc-test` and, before the list refreshes, click "Stop" on the screen; or stop the container twice | The error received shows untranslated under "Error received", with the exit code. The row shows the real state |
| 2 | Remove an image in use | Same behavior, with the row still in the list |
| 3 | Click "Dismiss" on the error | The entry is gone, the focus stays in the panel. Reloading does not bring the error back |
| 4 | Cause an error and reload without dismissing | The error stays in the panel |
| 5 | Stop the service with the screen open | The banner "The live connection to the service dropped" shows within 2 s. A click on any action shows "Could not reach the service" |
| 6 | Start the service again | The banner is gone within 2 s, and the data comes back without reloading |

## Change within 2 s

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | Create 30 containers: `for i in $(seq 30); do docker run -d --name cc-$i busybox sleep 3600; done` | The 30 show in the list |
| 2 | `docker stop -t 0 cc-7` from the terminal, with the screen open | The row changes to "Stopped" within 2 s |
| 3 | Click "Start" on the `cc-7` row | The row changes to "Running" within 2 s after the job ends |
| 4 | With 30 pods, repeat deleting a pod from the terminal | The pod list changes within 2 s |

Cleanup: `docker rm -f $(docker ps -aq --filter name=cc-)`, and delete the namespace, the Kubernetes resources and `~/cc-test`.

## Layout and identity

At 320, 390, 768, 1024 and 1280 px, on the containers, environment, Compose and pods screens (`rules/frontend.md`):

| # | Check | Expected result |
| --- | --- | --- |
| 1 | Horizontal scroll of the page | Never shows. A wide table scrolls only inside its card |
| 2 | Tables below about 1024 px | Secondary columns move into the first cell, with a label. Name, state and actions always visible |
| 3 | Tables at 320 px | Each row becomes a block: name, stacked data, state and buttons, without cutting text |
| 4 | Menu below 1024 px | The menu button opens the `<dialog>` drawer on `ink`. Esc closes it, and the focus goes back to the button |
| 5 | Top bar and menu | `ink` background, the project icon and, next to it, `Claude CLI Agents Workspace` with `Container Console` below, undistorted. The favicon is the same icon. The icon is decorative (empty alternative text): the name next to it is what the screen reader reads |
| 6 | Headings and text | Headings in Poppins 700, with no blue final dot and no text above the heading. The rest in Roboto. Corners of 5 px on buttons, fields and badges, and 20 px on cards |
| 7 | Focus with Tab on every screen | `#0076a3` ring in light, `#24bee6` in dark and on `ink`. The first Tab shows "Skip to content" |
| 8 | Status | Always icon and text |
| 9 | Long ids and paths | Monospaced, breaking only after `.`, `/` or `-`. A stretch without those characters scrolls in its own box |
| 10 | "Animations" toggle, in the menu | Off, the CPU and memory bars in a container's details change without a transition, the Compose groups open and close at once, and the choice persists. The same with the system's reduced motion |
| 11 | Browser console on every screen | No CSP violation, no font or image error |
| 12 | Phone or touch simulator | Fields at 16 px, no zoom on focus. Buttons at least 40 px |

## Theme

The GNOME appearance changes in Settings > Appearance. Start without a saved choice: in the browser console, run `localStorage.removeItem("container-console-docker-ce.theme")` and reload.

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | Without a saved choice, with the system in Light | Background `#f8f9fc`, white cards. The `Theme` field, in the side menu, shows "Follow the system" |
| 2 | With the screen open, switch the system to Dark | Without reloading, the background turns `#303841` and the cards `#343f4b`. Top bar and menu stay on `ink` |
| 3 | Switch the system back to Light | The screen goes back to light without reloading |
| 4 | With the system in Light, choose "Dark" | The screen turns dark right away |
| 5 | Reload the page | It stays dark, with no light flash first |
| 6 | Switch the system to Dark and then to Light | The screen stays dark in both cases: the choice wins over the system |
| 7 | With the system in Dark, choose "Light" and reload | It stays light, with no dark flash first |
| 8 | Switch the system to Light and back to Dark | The screen stays light in both cases |
| 9 | Choose "Follow the system", reload and switch the system | The choice persists, and the screen follows the system again |
| 10 | Keyboard only: Tab to `Theme`, arrows and Enter to switch | The focus ring shows on the field, and the theme changes |
| 11 | Below 1024 px, switch the theme in the menu drawer and widen the window to 1024 px or more | The theme changes with the drawer open, and the side menu field shows the same choice |
| 12 | In dark, go through containers, environment, Compose and pods | Readable text on cards, tables, notices and code blocks. Status always with icon and text, and the icon readable inside the badge |
| 13 | In dark, buttons, links and tabs | Primary button `#0076a3` with a `#24bee6` border. Links and the current tab in `#24bee6`. Disabled button distinguishable. Focus ring visible on every surface |
| 14 | In dark, open a confirmation dialog and hover table rows | The dialog stands out from the dimmed background. The row changes background, with readable text |
| 15 | In dark, look at the CPU and memory bars in a container's details and force an error on a field | Bar visible on the track. Error icon readable on the card |
| 16 | In both themes, open logs and terminal of a container | Dark background and light text, the same in both themes. Selected text stays readable |
| 17 | With the terminal open, switch the theme | The terminal does not change color, and the connection stays open |
| 18 | Browser console and network tab, in both themes | No CSP violation. `/theme-init.js` answers 200 |

## Language

| # | Steps | Expected result |
| --- | --- | --- |
| 1 | With the browser language in English (or any language that does not start with `pt`), open the console | Every text is in English: menu, headings, buttons, notices and the job descriptions in the Actions panel |
| 2 | Set the browser language to Portuguese (`pt` or `pt-BR`) and reload | Every text is in Brazilian Portuguese, for example "Ligado" in the top bar and "Seguir o sistema" in the `Tema` field. Numbers and dates use the Brazilian format |
| 3 | In both languages, cause a CLI error (for example, remove the `bridge` network) | The sentence of the error code is translated, and the error received shows as it came, untranslated |

Outside these lists and not verified: screen readers, browsers other than the one you use, and forced colors.
