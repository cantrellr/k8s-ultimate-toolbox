{{/*
Expand the name of the chart.
*/}}
{{- define "ultimate-k8s-toolbox.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "ultimate-k8s-toolbox.fullname" -}}
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
{{- define "ultimate-k8s-toolbox.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ultimate-k8s-toolbox.labels" -}}
helm.sh/chart: {{ include "ultimate-k8s-toolbox.chart" . }}
{{ include "ultimate-k8s-toolbox.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ultimate-k8s-toolbox.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ultimate-k8s-toolbox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ultimate-k8s-toolbox.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ultimate-k8s-toolbox.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Namespace to use: global.namespaceOverride (if set) otherwise the Helm release namespace.
This enables deploying to a specific namespace regardless of where helm is run from.
*/}}
{{- define "ultimate-k8s-toolbox.namespace" -}}
{{- if .Values.global.namespaceOverride }}
{{- .Values.global.namespaceOverride }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Image with optional registry prefix.
This is the key helper for offline/air-gapped deployments.
If global.imageRegistry is set, prepend it to the repository; otherwise use repository as-is.

Examples:
  1. Online (no global.imageRegistry):
     repository: "ultimate-k8s-toolbox"
     tag: "latest"
     Result: "ultimate-k8s-toolbox:latest"

  2. Offline with simple registry:
     global.imageRegistry: "myregistry.local:5000"
     repository: "ultimate-k8s-toolbox"
     tag: "latest"
     Result: "myregistry.local:5000/ultimate-k8s-toolbox:latest"

  3. Offline with project path:
     global.imageRegistry: "harbor.internal.com"
     repository: "platform/ultimate-k8s-toolbox"
     tag: "v1.0.2"
     Result: "harbor.internal.com/platform/ultimate-k8s-toolbox:v1.0.2"
*/}}
{{- define "ultimate-k8s-toolbox.image" -}}
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
Used when customCA.createSecret is true to create a single bundle file.
*/}}
{{- define "ultimate-k8s-toolbox.caBundle" -}}
{{- $bundle := "" }}
{{- range .Values.customCA.certificates }}
{{- $bundle = printf "%s%s\n" $bundle .content }}
{{- end }}
{{- $bundle }}
{{- end }}
