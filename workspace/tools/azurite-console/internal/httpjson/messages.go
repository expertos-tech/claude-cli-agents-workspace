package httpjson

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"maps"
	"net/http"
	"path"
	"strings"
)

// defaultLanguage answers a request that accepts no language of the catalog.
const defaultLanguage = "en"

// catalog holds the texts by language and key. It changes only through
// Register, during package initialization, so requests read it without a lock.
var catalog = map[string]map[string]string{
	"en": {
		CodeBadRequest:       "invalid request",
		CodeValidation:       "invalid data",
		CodeNotFound:         "not found",
		CodeMethodNotAllowed: "method not allowed",
		CodePayloadTooLarge:  "request body over the limit",
		CodeInternal:         "internal error",
	},
	"pt-BR": {
		CodeBadRequest:       "pedido inválido",
		CodeValidation:       "dados inválidos",
		CodeNotFound:         "não encontrado",
		CodeMethodNotAllowed: "método não permitido",
		CodePayloadTooLarge:  "corpo do pedido maior que o limite",
		CodeInternal:         "erro interno",
	},
}

// Register adds the texts of every <language>.json file at the root of fsys,
// each a flat object from key to text. Call it only during package
// initialization.
func Register(fsys fs.FS) error {
	files, err := fs.Glob(fsys, "*.json")
	if err != nil {
		return fmt.Errorf("list messages: %w", err)
	}
	for _, file := range files {
		data, err := fs.ReadFile(fsys, file)
		if err != nil {
			return fmt.Errorf("read messages: %w", err)
		}
		var messages map[string]string
		if err := json.Unmarshal(data, &messages); err != nil {
			return fmt.Errorf("parse messages %s: %w", file, err)
		}
		language := strings.TrimSuffix(path.Base(file), ".json")
		if catalog[language] == nil {
			catalog[language] = map[string]string{}
		}
		maps.Copy(catalog[language], messages)
	}
	return nil
}

// Message returns the text of key in the language of r, formatted with args.
// A key missing from that language falls back to the default language, and a
// key missing there too is returned as it is.
func Message(r *http.Request, key string, args ...any) string {
	text, ok := catalog[language(r)][key]
	if !ok {
		text, ok = catalog[defaultLanguage][key]
	}
	if !ok {
		return key
	}
	if len(args) == 0 {
		return text
	}
	return fmt.Sprintf(text, args...)
}

// language picks the first language of the Accept-Language header that the
// catalog has, comparing only the primary subtag and ignoring the q values.
func language(r *http.Request) string {
	for tag := range strings.SplitSeq(r.Header.Get("Accept-Language"), ",") {
		tag, _, _ = strings.Cut(tag, ";")
		primary := primarySubtag(strings.TrimSpace(tag))
		for known := range catalog {
			if strings.EqualFold(primary, primarySubtag(known)) {
				return known
			}
		}
	}
	return defaultLanguage
}

// primarySubtag is the part of a language tag before the first hyphen.
func primarySubtag(tag string) string {
	primary, _, _ := strings.Cut(tag, "-")
	return primary
}
