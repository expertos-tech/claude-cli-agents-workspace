package storage

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
)

func responseError(status int, code string) error {
	req := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:10001/devstoreaccount1/demo", nil)
	return runtime.NewResponseError(&http.Response{StatusCode: status, Header: http.Header{"X-Ms-Error-Code": {code}},
		Body: io.NopCloser(strings.NewReader("")), Request: req})
}

func TestClassify(t *testing.T) {
	cases := []struct {
		err  error
		want Kind
	}{
		{responseError(404, "QueueNotFound"), KindNotFound},
		{responseError(409, "TableAlreadyExists"), KindConflict},
		{responseError(412, "UpdateConditionNotSatisfied"), KindPrecondition},
		{responseError(400, "PopReceiptMismatch"), KindPrecondition},
		{responseError(400, "InvalidResourceName"), KindBadRequest},
		{responseError(416, "InvalidRange"), KindBadRequest},
		{responseError(503, "ServerBusy"), KindUnavailable},
		{errors.New("connection refused"), KindUnavailable},
	}
	for _, tc := range cases {
		if got := Classify(tc.err); got.Kind != tc.want {
			t.Errorf("Classify(%v) = %+v, want kind %d", tc.err, got, tc.want)
		}
	}
	if f := Classify(responseError(409, "ContainerAlreadyExists")); f.Status != 409 || f.Code != "ContainerAlreadyExists" {
		t.Errorf("Classify kept %+v", f)
	}
}

func TestWritableDropsWhatTheServiceManages(t *testing.T) {
	in := `{"odata.etag":"W/\"1\"","odata.metadata":"x","PartitionKey":"a","RowKey":"b","Timestamp":"2026-10-28T00:00:00Z",` +
		`"Timestamp@odata.type":"Edm.DateTime","Count":"5","Count@odata.type":"Edm.Int64","Name":"fictitious"}`
	out, err := writable(json.RawMessage(in))
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(out, &m); err != nil {
		t.Fatal(err)
	}
	for _, k := range []string{"odata.etag", "odata.metadata", "Timestamp", "Timestamp@odata.type"} {
		if _, ok := m[k]; ok {
			t.Errorf("%s kept", k)
		}
	}
	for _, k := range []string{"PartitionKey", "RowKey", "Count", "Count@odata.type", "Name"} {
		if _, ok := m[k]; !ok {
			t.Errorf("%s dropped", k)
		}
	}
	for _, bad := range []string{`[1]`, `{"PartitionKey":"a"}`, `{"PartitionKey":1,"RowKey":"b"}`, `nope`} {
		if _, err := writable(json.RawMessage(bad)); !errors.Is(err, ErrEntityInvalid) {
			t.Errorf("writable(%s) = %v, want ErrEntityInvalid", bad, err)
		}
	}
}
