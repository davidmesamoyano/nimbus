{{/*
Configuración final de la app: valores por defecto + app.yaml + ajustes del
entorno actual (environments.<dev|prod>). Se devuelve como YAML para poder
usarla en cada plantilla con:  $c := include "nimbus.config" . | fromYaml
*/}}
{{- define "nimbus.config" -}}
{{- $base := omit .Values "environments" -}}
{{- $override := dict -}}
{{- if and .Values.environment .Values.environments -}}
{{- if hasKey .Values.environments .Values.environment -}}
{{- $override = index .Values.environments .Values.environment | default dict -}}
{{- end -}}
{{- end -}}
{{- $config := mergeOverwrite (deepCopy $base) (deepCopy $override) -}}
{{- $_ := required "app.yaml: el campo 'name' es obligatorio" $config.name -}}
{{- $_ := required "app.yaml: el campo 'image.repository' es obligatorio" $config.image.repository -}}
{{- toYaml $config -}}
{{- end -}}

{{/* Etiquetas que identifican los pods de una app (selector inmutable) */}}
{{- define "nimbus.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
nimbus.io/app: {{ .name }}
{{- end -}}

{{/* Etiquetas comunes. Uso: include "nimbus.labels" (dict "c" $c "root" $) */}}
{{- define "nimbus.labels" -}}
{{ include "nimbus.selectorLabels" .c }}
app.kubernetes.io/managed-by: nimbus
app.kubernetes.io/version: {{ .c.image.tag | quote }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version }}
nimbus.io/environment: {{ .root.Values.environment | default "local" }}
{{- end -}}

{{/* Recursos predefinidos según el tamaño elegido en app.yaml */}}
{{- define "nimbus.resources" -}}
{{- $presets := dict
  "small"  (dict "requests" (dict "cpu" "25m"  "memory" "48Mi")  "limits" (dict "memory" "96Mi"))
  "medium" (dict "requests" (dict "cpu" "100m" "memory" "128Mi") "limits" (dict "memory" "256Mi"))
  "large"  (dict "requests" (dict "cpu" "250m" "memory" "256Mi") "limits" (dict "memory" "512Mi"))
-}}
{{- toYaml (index $presets .) -}}
{{- end -}}
