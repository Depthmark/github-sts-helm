{{/*
Expand the name of the chart.
*/}}
{{- define "github-sts.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "github-sts.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "github-sts.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "github-sts.labels" -}}
helm.sh/chart: {{ include "github-sts.chart" . }}
{{ include "github-sts.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "github-sts.selectorLabels" -}}
app.kubernetes.io/name: {{ include "github-sts.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "github-sts.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "github-sts.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper image name.
When `image.digest` is set, pin by digest (`repo@sha256:...`) and ignore the
tag — digest pinning is required by tools like cosign / Kyverno verifyImages
and is what `kubectl describe` ends up resolving to anyway.
*/}}
{{- define "github-sts.image" -}}
{{- $repo := .Values.image.repository -}}
{{- if .Values.image.registry -}}
{{- $repo = printf "%s/%s" .Values.image.registry .Values.image.repository -}}
{{- end -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" $repo .Values.image.digest -}}
{{- else -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end }}

{{/*
Return true if at least one GitHub App is configured.
*/}}
{{- define "github-sts.hasApps" -}}
{{- if .Values.github.apps -}}
true
{{- end -}}
{{- end }}

{{/*
Whether client certificate verification (mTLS) is active. Client auth only
means anything once the server is serving TLS.
*/}}
{{- define "github-sts.mtlsEnabled" -}}
{{- if and .Values.tls.enabled .Values.tls.clientAuth.enabled -}}
true
{{- end -}}
{{- end }}

{{/*
Name of the container/Service port. Mesh implementations and some ingress
controllers infer the wire protocol from this name, so it follows the scheme
the pod actually serves.
*/}}
{{- define "github-sts.portName" -}}
{{- if .Values.tls.enabled -}}
https
{{- else -}}
http
{{- end -}}
{{- end }}

{{/*
URL scheme clients should use to reach the pod.
*/}}
{{- define "github-sts.scheme" -}}
{{- if .Values.tls.enabled -}}
https
{{- else -}}
http
{{- end -}}
{{- end }}

{{/*
Absolute path of a TLS file inside the container, given the key it is
projected under.
*/}}
{{- define "github-sts.tlsPath" -}}
{{- printf "%s/%s" (trimSuffix "/" .ctx.Values.tls.mountPath) .key -}}
{{- end }}

{{/*
Secret holding the client CA bundle. Falls back to the serving certificate's
Secret, which is where cert-manager writes `ca.crt` by default.
*/}}
{{- define "github-sts.clientCASecret" -}}
{{- .Values.tls.clientAuth.existingSecret | default .Values.tls.existingSecret -}}
{{- end }}

{{/*
Resolved probe transport: httpGet or tcpSocket.
*/}}
{{- define "github-sts.probeMode" -}}
{{- $mode := .Values.probes.mode | default "auto" -}}
{{- if eq $mode "auto" -}}
{{- if include "github-sts.mtlsEnabled" . -}}
tcpSocket
{{- else -}}
httpGet
{{- end -}}
{{- else -}}
{{- $mode -}}
{{- end -}}
{{- end }}

{{/*
Probe action block for a given path. Emits a tcpSocket probe when the listener
requires a client certificate the kubelet cannot provide.
Usage: {{ include "github-sts.probeAction" (dict "ctx" $ "path" "/ready") }}
*/}}
{{- define "github-sts.probeAction" -}}
{{- $ctx := .ctx -}}
{{- if eq (include "github-sts.probeMode" $ctx) "tcpSocket" -}}
tcpSocket:
  port: {{ include "github-sts.portName" $ctx }}
{{- else -}}
httpGet:
  path: {{ .path }}
  port: {{ include "github-sts.portName" $ctx }}
  {{- if $ctx.Values.tls.enabled }}
  scheme: HTTPS
  {{- end }}
  {{- if .headerToken }}
  httpHeaders:
    - name: Authorization
      value: {{ printf "Bearer %s" .headerToken | quote }}
  {{- end }}
{{- end -}}
{{- end }}

{{/* Effective inline metrics token, including the deprecated values key. */}}
{{- define "github-sts.endpointAuthMetricsToken" -}}
{{- .Values.endpointAuth.metricsToken | default .Values.metrics.authToken -}}
{{- end }}

{{/*
Whether an endpoint is authenticated. An inline token is proof on its own,
because the chart writes the Secret itself. An `existingSecret` is opaque to
the chart, so the key names stand in for its contents: a non-empty key asserts
the token is there, and clearing a key says this Secret carries no token for
that endpoint. That distinction matters for the monitors — the Prometheus
Operator rejects a `bearerTokenSecret` whose key is missing, so guessing a key
into an external Secret breaks scraping outright.
*/}}
{{- define "github-sts.healthEndpointAuthEnabled" -}}
{{- if or .Values.endpointAuth.healthToken (and .Values.endpointAuth.existingSecret .Values.endpointAuth.healthKey) -}}
true
{{- end -}}
{{- end }}

{{- define "github-sts.metricsEndpointAuthEnabled" -}}
{{- if or (include "github-sts.endpointAuthMetricsToken" .) (and .Values.endpointAuth.existingSecret .Values.endpointAuth.metricsKey) -}}
true
{{- end -}}
{{- end }}

{{/* Whether any endpoint token source is configured. */}}
{{- define "github-sts.endpointAuthEnabled" -}}
{{- if or (include "github-sts.healthEndpointAuthEnabled" .) (include "github-sts.metricsEndpointAuthEnabled" .) -}}
true
{{- end -}}
{{- end }}

{{/* Render an endpoint-auth Secret only for inline token values. */}}
{{- define "github-sts.createEndpointAuthSecret" -}}
{{- if and (not .Values.endpointAuth.existingSecret) (or .Values.endpointAuth.healthToken (include "github-sts.endpointAuthMetricsToken" .)) -}}
true
{{- end -}}
{{- end }}

{{/* Secret containing endpoint bearer tokens. */}}
{{- define "github-sts.endpointAuthSecretName" -}}
{{- .Values.endpointAuth.existingSecret | default (printf "%s-endpoint-auth" (include "github-sts.fullname" .)) -}}
{{- end }}

{{/* Reject ambiguous endpoint-auth values and impossible liveness probes. */}}
{{- define "github-sts.validateEndpointAuth" -}}
{{- if and .Values.metrics.authToken .Values.endpointAuth.metricsToken -}}
{{- fail "metrics.authToken is deprecated and conflicts with endpointAuth.metricsToken — set only endpointAuth.metricsToken" -}}
{{- end -}}
{{- if and .Values.metrics.authToken .Values.endpointAuth.existingSecret -}}
{{- fail "metrics.authToken is deprecated and cannot be combined with endpointAuth.existingSecret — move the token into that Secret under endpointAuth.metricsKey and clear metrics.authToken" -}}
{{- end -}}
{{- if and (include "github-sts.healthEndpointAuthEnabled" .) (not .Values.endpointAuth.healthToken) .Values.probes.liveness.enabled (eq (include "github-sts.probeMode" .) "httpGet") -}}
{{- fail "endpointAuth.existingSecret cannot supply the liveness HTTP header — set endpointAuth.healthToken inline, clear endpointAuth.healthKey if that Secret holds no health token, or set probes.mode to tcpSocket" -}}
{{- end -}}
{{- if and .Values.endpointAuth.healthToken (not .Values.endpointAuth.healthKey) -}}
{{- fail "endpointAuth.healthToken needs endpointAuth.healthKey to name the Secret key holding it" -}}
{{- end -}}
{{- if and (include "github-sts.endpointAuthMetricsToken" .) (not .Values.endpointAuth.metricsKey) -}}
{{- fail "endpointAuth.metricsToken needs endpointAuth.metricsKey to name the Secret key holding it" -}}
{{- end -}}
{{- if and .Values.endpointAuth.existingSecret (not .Values.endpointAuth.healthKey) (not .Values.endpointAuth.metricsKey) -}}
{{- fail "endpointAuth.existingSecret has no effect with both endpointAuth.healthKey and endpointAuth.metricsKey cleared — name at least one key the Secret holds" -}}
{{- end -}}
{{- end }}

{{/*
Fail fast on TLS settings the application would reject at startup, or that
would leave the pod unable to serve at all. Rendering an invalid config into a
running release is worse than failing the upgrade.
*/}}
{{- define "github-sts.validateTls" -}}
{{- $tls := .Values.tls -}}
{{- if $tls.enabled -}}
{{- if not $tls.existingSecret -}}
{{- fail "tls.enabled requires tls.existingSecret — the chart does not generate certificates" -}}
{{- end -}}
{{- if not (has ($tls.minVersion | toString) (list "1.2" "1.3")) -}}
{{- fail (printf "tls.minVersion must be \"1.2\" or \"1.3\" (got %q)" ($tls.minVersion | toString)) -}}
{{- end -}}
{{- if and (eq ($tls.minVersion | toString) "1.3") $tls.cipherSuites -}}
{{- fail "tls.cipherSuites has no effect with tls.minVersion \"1.3\" and is rejected by github-sts — leave it empty" -}}
{{- end -}}
{{- if and $tls.clientAuth.enabled (not (include "github-sts.clientCASecret" .)) -}}
{{- fail "tls.clientAuth.enabled requires tls.clientAuth.existingSecret (or tls.existingSecret) to hold the client CA bundle" -}}
{{- end -}}
{{- else if $tls.clientAuth.enabled -}}
{{- fail "tls.clientAuth.enabled requires tls.enabled — client certificates can only be verified on a TLS listener" -}}
{{- end -}}
{{- if not (has (.Values.probes.mode | default "auto") (list "auto" "httpGet" "tcpSocket")) -}}
{{- fail (printf "probes.mode must be one of auto, httpGet, tcpSocket (got %q)" .Values.probes.mode) -}}
{{- end -}}
{{- end }}

{{/*
Whether to render the `helm test` hook pods. mTLS turns them off: the hook pods
carry no client certificate, so every request would be rejected during the
handshake and `helm test` would always fail.
*/}}
{{- define "github-sts.renderTests" -}}
{{- if and .Values.tests.enabled (not (include "github-sts.mtlsEnabled" .)) -}}
true
{{- end -}}
{{- end }}

{{/*
Shell snippet for the test hook pods that puts the response body in $RESPONSE.
Prefers curl when the image ships it and falls back to BusyBox wget, so the
image can be swapped without editing the templates. Certificate verification is
skipped: the Service DNS name rarely matches the SAN of a cert issued for the
public ingress hostname, and these hooks assert the endpoint answers, not the
identity of the certificate.
Usage: {{ include "github-sts.testFetch" (dict "ctx" $ "path" "/health") }}
*/}}
{{- define "github-sts.testFetch" -}}
{{- $ctx := .ctx -}}
{{- $url := printf "%s://%s:%v%s" (include "github-sts.scheme" $ctx) (include "github-sts.fullname" $ctx) $ctx.Values.service.port .path -}}
URL="{{ $url }}"
AUTH=""
if [ -n "${STS_TEST_TOKEN:-}" ]; then AUTH="Authorization: Bearer ${STS_TEST_TOKEN}"; fi
if command -v curl >/dev/null 2>&1; then
  RESPONSE=$(curl -fsS {{ if $ctx.Values.tls.enabled }}-k {{ end }}${AUTH:+-H "$AUTH"} "$URL")
else
  RESPONSE=$(wget -qO- {{ if $ctx.Values.tls.enabled }}--no-check-certificate {{ end }}${AUTH:+--header="$AUTH"} "$URL")
fi
{{- end }}

{{/*
Normalized instance list for one logical app. An app is backed either by a
single GitHub App (`appId` / `existingSecret`) or by a pool of several
(`instances`); the server treats the first form as a pool of one, and so does
this helper, so every template iterates one shape instead of branching.

Each element carries the private key's location in both forms the templates
need: `relPath` for the volume item, `keyPath` for the ConfigMap.

Pool members get their own `<appId>/` directory under the app mount. The
directory is keyed on `appId` rather than the instance name because `appId` is
what the server requires to be unique within a pool, and because an instance
name may legally contain `/`, which would turn one path segment into two.

Usage:
  {{ include "github-sts.appInstances" (dict "name" $appName "app" $appConfig) | fromYamlArray }}
*/}}
{{- define "github-sts.appInstances" -}}
{{- $mountPath := printf "/etc/github-sts/apps/%s" .name -}}
{{- $app := .app -}}
{{- if $app.instances -}}
{{- range $app.instances }}
{{- $appID := .appId | int64 }}
{{- $secretKey := .secretPrivateKeyKey | default "github-app-private-key" }}
{{- $relPath := printf "%d/%s" $appID $secretKey }}
- name: {{ .name | default (printf "%d" $appID) | quote }}
  appId: {{ $appID }}
  existingSecret: {{ .existingSecret | quote }}
  secretKey: {{ $secretKey | quote }}
  relPath: {{ $relPath | quote }}
  keyPath: {{ printf "%s/%s" $mountPath $relPath | quote }}
{{- end }}
{{- else -}}
{{- $appID := $app.appId | int64 }}
{{- $secretKey := $app.secretPrivateKeyKey | default "github-app-private-key" }}
- name: {{ printf "%d" $appID | quote }}
  appId: {{ $appID }}
  existingSecret: {{ $app.existingSecret | quote }}
  secretKey: {{ $secretKey | quote }}
  relPath: {{ $secretKey | quote }}
  keyPath: {{ printf "%s/%s" $mountPath $secretKey | quote }}
{{- end -}}
{{- end }}

{{/*
Whether any configured app is backed by a pool of instances.
*/}}
{{- define "github-sts.hasPooledApp" -}}
{{- range $appName, $app := .Values.github.apps -}}
{{- if $app.instances -}}
true
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Fail fast on app configurations the server would reject at startup, or that
would render a Deployment referencing a Secret by an empty name. These mirror
the server's own validation: catching them at `helm upgrade` keeps a bad value
out of a running release instead of turning it into a CrashLoopBackOff.
*/}}
{{- define "github-sts.validateApps" -}}
{{- range $appName, $app := .Values.github.apps -}}
{{- $hasPool := gt (len ($app.instances | default list)) 0 -}}
{{- $hasFlat := or $app.appId $app.existingSecret $app.secretPrivateKeyKey -}}
{{- if and $hasPool $hasFlat -}}
{{- fail (printf "github.apps.%s: appId/existingSecret/secretPrivateKeyKey and instances are mutually exclusive — a pooled app carries its credentials per instance" $appName) -}}
{{- end -}}
{{- if not (or $hasPool $hasFlat) -}}
{{- fail (printf "github.apps.%s: set appId and existingSecret (one GitHub App), or instances (a pool of several)" $appName) -}}
{{- end -}}
{{- if $hasPool -}}
{{- $seenID := dict -}}
{{- $seenName := dict -}}
{{- range $i, $inst := $app.instances -}}
{{- $label := $inst.name | default (printf "#%d" $i) -}}
{{- if not $inst.appId -}}
{{- fail (printf "github.apps.%s.instances[%d]: appId is required" $appName $i) -}}
{{- end -}}
{{- if not $inst.existingSecret -}}
{{- fail (printf "github.apps.%s: instance %s: existingSecret is required — the chart never creates the Secret holding a private key" $appName $label) -}}
{{- end -}}
{{- if $inst.name -}}
{{- if gt (len $inst.name) 100 -}}
{{- fail (printf "github.apps.%s: instance %s: name exceeds maximum length of 100 (it becomes a Prometheus label value)" $appName $label) -}}
{{- end -}}
{{- if not (regexMatch "^[a-zA-Z0-9._/-]+$" $inst.name) -}}
{{- fail (printf "github.apps.%s: instance %s: name must match [a-zA-Z0-9._/-]+ (it becomes a Prometheus label value)" $appName $label) -}}
{{- end -}}
{{- end -}}
{{- $id := printf "%d" ($inst.appId | int64) -}}
{{- if hasKey $seenID $id -}}
{{- fail (printf "github.apps.%s: duplicate appId %s within pool (instances %s and %s)" $appName $id (get $seenID $id) $label) -}}
{{- end -}}
{{- $_ := set $seenID $id $label -}}
{{- $effective := $inst.name | default $id -}}
{{- if hasKey $seenName $effective -}}
{{- fail (printf "github.apps.%s: instance name %q used by both instances %s and %s" $appName $effective (get $seenName $effective) $label) -}}
{{- end -}}
{{- $_ := set $seenName $effective $label -}}
{{- end -}}
{{- else -}}
{{- if not $app.appId -}}
{{- fail (printf "github.apps.%s: appId is required" $appName) -}}
{{- end -}}
{{- if not $app.existingSecret -}}
{{- fail (printf "github.apps.%s: existingSecret is required — the chart never creates the Secret holding a private key" $appName) -}}
{{- end -}}
{{- end -}}
{{- with $app.rotation -}}
{{- if not $hasPool -}}
{{- fail (printf "github.apps.%s: rotation has no effect without instances, and the server rejects it on a single-App config" $appName) -}}
{{- end -}}
{{- with .strategy -}}
{{- if not (has . (list "round_robin" "rate_limit_aware")) -}}
{{- fail (printf "github.apps.%s: rotation.strategy must be round_robin or rate_limit_aware (got %q)" $appName .) -}}
{{- end -}}
{{- end -}}
{{- with .minRemainingPct -}}
{{- if or (lt (float64 .) 0.0) (ge (float64 .) 100.0) -}}
{{- fail (printf "github.apps.%s: rotation.minRemainingPct must be in [0,100) (got %v)" $appName .) -}}
{{- end -}}
{{- end -}}
{{- with .maxAttempts -}}
{{- if lt (int64 .) 1 -}}
{{- fail (printf "github.apps.%s: rotation.maxAttempts must be >= 1 (got %v)" $appName .) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- with $app.policyResolution -}}
{{- if and (not $app.orgPolicyRepo) (has . (list "org_first" "org_only")) -}}
{{- fail (printf "github.apps.%s: policyResolution %q requires orgPolicyRepo — both modes read the organization policy repository" $appName .) -}}
{{- end -}}
{{- if not (has . (list "org_first" "repo_first" "org_only")) -}}
{{- fail (printf "github.apps.%s: policyResolution must be one of org_first, repo_first, org_only (got %q)" $appName .) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/* Secret-backed bearer token for an endpoint test hook. */}}
{{- define "github-sts.testEnv" -}}
env:
  - name: STS_TEST_TOKEN
    valueFrom:
      secretKeyRef:
        name: {{ include "github-sts.endpointAuthSecretName" .ctx }}
        key: {{ .key }}
        optional: true
{{- end }}
