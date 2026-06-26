{{/*
Expand the name of the chart.
*/}}
{{- define "k8s-ultimate-toolbox.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "k8s-ultimate-toolbox.fullname" -}}
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
{{- define "k8s-ultimate-toolbox.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "k8s-ultimate-toolbox.labels" -}}
helm.sh/chart: {{ include "k8s-ultimate-toolbox.chart" . }}
{{ include "k8s-ultimate-toolbox.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "k8s-ultimate-toolbox.selectorLabels" -}}
app.kubernetes.io/name: {{ include "k8s-ultimate-toolbox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "k8s-ultimate-toolbox.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "k8s-ultimate-toolbox.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Namespace to use: global.namespaceOverride if set; otherwise the Helm release namespace.
*/}}
{{- define "k8s-ultimate-toolbox.namespace" -}}
{{- if .Values.global.namespaceOverride }}
{{- .Values.global.namespaceOverride }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Image with optional registry prefix for offline/air-gapped deployments.

Examples:
  Online:
    repository: "k8s-ultimate-toolbox"
    tag: "v1.2.0"
    Result: "k8s-ultimate-toolbox:v1.2.0"

  Offline with simple registry:
    global.imageRegistry: "myregistry.local:5000"
    repository: "k8s-ultimate-toolbox"
    tag: "v1.2.0"
    Result: "myregistry.local:5000/k8s-ultimate-toolbox:v1.2.0"

  Offline with project path:
    global.imageRegistry: "harbor.internal.com"
    repository: "platform/k8s-ultimate-toolbox"
    tag: "v1.2.0"
    Result: "harbor.internal.com/platform/k8s-ultimate-toolbox:v1.2.0"
*/}}
{{- define "k8s-ultimate-toolbox.image" -}}
{{- $registry := .Values.global.imageRegistry | default "" }}
{{- $repository := .Values.image.repository }}
{{- $tag := .Values.image.tag | default .Chart.AppVersion }}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{/*
Generate combined CA bundle from all certificates.
*/}}
{{- define "k8s-ultimate-toolbox.caBundle" -}}
{{- $bundle := "" }}
{{- range .Values.customCA.certificates }}
{{- $bundle = printf "%s%s\n" $bundle .content }}
{{- end }}
{{- $bundle }}
{{- end }}
