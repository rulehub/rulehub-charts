{{- /* Integrity ConfigMap disabled pending parser-safe embedding
if and .Values.build .Values.build.exportIntegrityConfigMap (.Values.build.integritySha256) (ne (.Values.build.integritySha256 | toString) "") -}}
{{/* include "policy-sets.integrity.configmap" . */}}
{{- /* end */ -}}
