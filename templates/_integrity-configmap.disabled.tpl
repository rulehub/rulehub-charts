{{/* Disabled integrity ConfigMap wrapper (previously integrity-configmap.yaml). Kept for future reintroduction. */}}
{{/* Original conditional:
if and .Values.build .Values.build.exportIntegrityConfigMap (.Values.build.integritySha256) (ne (.Values.build.integritySha256 | toString) "") */}}
{{/* include "policy-sets.integrity.configmap" . */}}
