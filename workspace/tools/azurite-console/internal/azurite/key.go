package azurite

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"strings"
)

// LookupKey returns the account key from the environment or, when it is not
// set there, from the KEY=VALUE file at envFile (the filled file of the
// workspace's custom layer, custom/env/azurite-console.env, given by the run
// command). An empty envFile reads only the environment. The value is never
// printed, and no folder is searched for a .env file.
func LookupKey(envFile string) (string, error) {
	if v := strings.TrimSpace(os.Getenv(KeyEnv)); v != "" {
		return v, nil
	}
	if envFile == "" {
		return "", fmt.Errorf("%s not set in the environment; set it, or pass -env-file custom/env/azurite-console.env", KeyEnv)
	}
	if _, err := os.Stat(envFile); err != nil {
		return "", fmt.Errorf("env file %s: %w; create it with /local-env tools/azurite-console", envFile, err)
	}
	v, err := fromDotEnv(envFile, KeyEnv)
	if err != nil {
		return "", err
	}
	if v == "" {
		return "", fmt.Errorf("%s is empty in %s", KeyEnv, envFile)
	}
	return v, nil
}

// fromDotEnv reads a KEY=VALUE file and returns the value of name, or "" when
// the file or the key is missing. Quotes around the value are removed.
func fromDotEnv(path, name string) (string, error) {
	f, err := os.Open(path) //nolint:gosec // path is the env file the run command names
	if errors.Is(err, os.ErrNotExist) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok || strings.TrimSpace(k) != name {
			continue
		}
		return strings.Trim(strings.TrimSpace(v), `"'`), nil
	}
	return "", sc.Err()
}
