{{- define "enterprise-rag-retrieval.secretName" -}}
{{- if .Values.secret.existingSecret -}}
{{- .Values.secret.existingSecret -}}
{{- else -}}
enterprise-rag-retrieval
{{- end -}}
{{- end -}}
