module container-console-colima

go 1.27.3

// web/node_modules may hold .go files that are not part of this module.
ignore ./web

require (
	github.com/coder/websocket v1.8.15
	github.com/creack/pty v1.1.24
)
