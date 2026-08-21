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
if command -v curl >/dev/null 2>&1; then
  RESPONSE=$(curl -fsS {{ if $ctx.Values.tls.enabled }}-k {{ end }}"$URL")
else
  RESPONSE=$(wget -qO- {{ if $ctx.Values.tls.enabled }}--no-check-certificate {{ end }}"$URL")
fi
{{- end }}
