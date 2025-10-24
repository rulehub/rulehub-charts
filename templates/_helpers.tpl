{{/* Helper templates for policy-sets chart (clean rebuild) */}}

{{/* DRY helper: ensure chart/version label is present on metadata (idempotent). Returns mutated metadata as YAML. */}}
{{- define "policy-sets.meta.ensureChartVersionLabel" -}}
{{- $meta := (.meta | default (dict)) -}}
{{- $root := .root -}}
{{- $_ := set $meta "labels" ((get $meta "labels" | default (dict))) -}}
{{- $labels := get $meta "labels" -}}
{{- if not (hasKey $labels "chart/version") -}}{{- $_ := set $labels "chart/version" $root.Chart.Version -}}{{- end -}}
{{ toYaml $meta }}
{{- end -}}

{{/* normalizePolicies: canonicalize policy config keys and merge duplicates */}}
{{- define "policy-sets.normalizePolicies" -}}
{{- $in := .policies | default (dict) -}}
{{- $out := dict -}}
{{- $deprecated := list -}}
{{- range $k, $v := $in }}
	{{- $suffix := "" -}}
	{{- if hasSuffix "-constraint" $k -}}
		{{- $suffix = "-constraint" -}}
	{{- else if hasSuffix "-policy" $k -}}
		{{- $suffix = "-policy" -}}
	{{- end -}}
	{{- $base := $k -}}
	{{- if $suffix -}}{{- $base = trimSuffix $suffix $k -}}{{- end -}}
	{{- $canonicalBase := replace $base "_" "-" -}}
	{{- $canonical := printf "%s%s" $canonicalBase $suffix -}}
	{{- if ne $canonical $k -}}{{- $deprecated = append $deprecated $k -}}{{- end -}}
	{{- $existing := (get $out $canonical) | default (dict) -}}
	{{- $merged := dict -}}
	{{- range $ek, $ev := $existing -}}{{- $_ := set $merged $ek $ev -}}{{- end -}}
	{{- range $vk, $vv := $v -}}
		{{- if or (not (hasKey $merged $vk)) (and (ne $canonical $k) (not (hasKey $existing $vk))) -}}{{- $_ := set $merged $vk $vv -}}{{- end -}}
	{{- end -}}
	{{- $_ := set $out $canonical $merged -}}
{{- end -}}
{{- toYaml (dict "policies" $out "deprecated" $deprecated) -}}
{{- end -}}

{{/* Integrity ConfigMap helper (only content; conditional wrapper lives in .yaml template) */}}
{{- define "policy-sets.integrity.configmap" -}}
apiVersion: v1
kind: ConfigMap
metadata:
	name: {{ (default "policy-sets-integrity" .Values.build.integrityConfigMapName) | trunc 63 | trimSuffix "-" }}
	labels:
		chart/version: {{ .Chart.Version | quote }}
	annotations:
		policy-sets/build.integrity.sha256: {{ .Values.build.integritySha256 | quote }}
{{- if and (.Values.build.commitSha) (ne (.Values.build.commitSha | toString) "") }}
		policy-sets/build.commit: {{ .Values.build.commitSha | quote }}
{{- end }}
{{- if and (.Values.build.timestamp) (ne (.Values.build.timestamp | toString) "") }}
		policy-sets/build.timestamp: {{ .Values.build.timestamp | quote }}
{{- end }}
data:
	integrity.sha256: {{ .Values.build.integritySha256 | quote }}
{{- end -}}

{{/* Kyverno render helper (parsed): parse YAML, normalize name, inject validationFailureAction & chart/version label */}}
{{- define "policy-sets.kyverno.render" -}}
{{- $bytes := .bytes -}}
{{- $root := .root -}}
{{- $filename := .name -}}
{{- $action := (.action | default "") -}}
{{- $doc := fromYaml ($bytes | toString) -}}
{{- if not $doc }}{{- else -}}
	{{- if ne (get $doc "kind" | default "") "ClusterPolicy" -}}
		{{- /* Only render ClusterPolicy */ -}}
	{{- else -}}
		{{- $meta := (get $doc "metadata" | default (dict)) -}}
		{{- $name := (get $meta "name" | default "") -}}
		{{- if or (eq $name "") (eq $name "-") -}}
			{{- $base := $filename -}}
			{{- if hasSuffix "-policy" $base -}}{{- $base = trimSuffix "-policy" $base -}}{{- end -}}
			{{- $_ := set $meta "name" $base -}}
			{{- $name = $base -}}
		{{- end -}}
		{{- /* Normalize underscores in name to hyphens, preserving original */ -}}
		{{- if and (ne $name "") (contains "_" $name) -}}
			{{- $_ := set $meta "annotations" ((get $meta "annotations" | default (dict))) -}}
			{{- $anns := get $meta "annotations" -}}
			{{- $_ := set $anns "policy-sets/original-name" $name -}}
			{{- $_ := set $meta "name" (replace "_" "-" $name) -}}
		{{- end -}}
		{{- if ne $action "" -}}
			{{- $spec := (get $doc "spec" | default (dict)) -}}
			{{- $_ := set $spec "validationFailureAction" $action -}}
			{{- $_ := set $doc "spec" $spec -}}
		{{- end -}}
		{{- $meta = (include "policy-sets.meta.ensureChartVersionLabel" (dict "meta" $meta "root" $root) | fromYaml) -}}
		{{- /* Inject build annotations similar to Gatekeeper */ -}}
		{{- $_ := set $meta "annotations" ((get $meta "annotations" | default (dict))) -}}
		{{- $anns := get $meta "annotations" -}}
		{{- if and ($root.Values.build) ($root.Values.build.commitSha) (ne ($root.Values.build.commitSha | toString) "") -}}
			{{- if not (hasKey $anns "policy-sets/build.commit") -}}{{- $_ := set $anns "policy-sets/build.commit" ($root.Values.build.commitSha | toString) -}}{{- end -}}
		{{- end -}}
		{{- if and ($root.Values.build) ($root.Values.build.timestamp) (ne ($root.Values.build.timestamp | toString) "") -}}
			{{- if not (hasKey $anns "policy-sets/build.timestamp") -}}{{- $_ := set $anns "policy-sets/build.timestamp" ($root.Values.build.timestamp | toString) -}}{{- end -}}
		{{- end -}}
		{{- if and ($root.Values.build) ($root.Values.build.integritySha256) (ne ($root.Values.build.integritySha256 | toString) "") -}}
			{{- if not (hasKey $anns "policy-sets/build.integrity.sha256") -}}{{- $_ := set $anns "policy-sets/build.integrity.sha256" ($root.Values.build.integritySha256 | toString) -}}{{- end -}}
		{{- end -}}
		{{- $_ := set $doc "metadata" $meta -}}
		{{ toYaml $doc }}
	{{- end -}}
{{- end -}}
{{- end -}}

{{/* Gatekeeper render helper: ensure name & inject chart/version label */}}
{{- define "policy-sets.gk.render" -}}
{{- $bytes := .bytes -}}
{{- $root := .root | default $ -}}
{{- $doc := fromYaml ($bytes | toString) -}}
{{- if not (eq (get $doc "kind" | default "") "<Kind>") -}}
	{{- $meta := (get $doc "metadata" | default (dict)) -}}
	{{- $rawName := (get $meta "name" | default "") -}}
	{{- if or (eq $rawName "") (eq $rawName "-") -}}
		{{- $anns := (get $meta "annotations" | default (dict)) -}}
		{{- $rid := (get $anns "rulehub.id" | default "") -}}
		{{- if ne $rid "" -}}
			{{- $derived1 := (replace "." "-" $rid) -}}
			{{- $derived := (replace "_" "-" $derived1) -}}
			{{- if or (eq $derived "") (eq $derived "-") -}}
				{{- $hash := (sha256sum $rid | trunc 8) -}}
				{{- $derived = printf "policy-%s" $hash -}}
			{{- end -}}
			{{- $_ := set $meta "name" $derived -}}
			{{- $_ := set $doc "metadata" $meta -}}
			{{- $rawName = $derived -}}
		{{- end -}}
	{{- end -}}
	{{- if and (ne $rawName "") (contains "_" $rawName) -}}
		{{- $_ := set $meta "annotations" ((get $meta "annotations" | default (dict))) -}}
		{{- $anns := get $meta "annotations" -}}
		{{- $_ := set $anns "policy-sets/original-name" $rawName -}}
		{{- $_ := set $meta "name" (replace "_" "-" $rawName) -}}
		{{- $_ := set $doc "metadata" $meta -}}
	{{- end -}}
	{{- /* Inject chart/version label */ -}}
	{{- $meta = (include "policy-sets.meta.ensureChartVersionLabel" (dict "meta" $meta "root" $root) | fromYaml) -}}
	{{- /* Build annotations like for Kyverno */ -}}
	{{- $_ := set $meta "annotations" ((get $meta "annotations" | default (dict))) -}}
	{{- $anns := get $meta "annotations" -}}
	{{- if and ($root.Values.build) ($root.Values.build.commitSha) (ne ($root.Values.build.commitSha | toString) "") -}}
		{{- if not (hasKey $anns "policy-sets/build.commit") -}}{{- $_ := set $anns "policy-sets/build.commit" ($root.Values.build.commitSha | toString) -}}{{- end -}}
	{{- end -}}
	{{- if and ($root.Values.build) ($root.Values.build.timestamp) (ne ($root.Values.build.timestamp | toString) "") -}}
		{{- if not (hasKey $anns "policy-sets/build.timestamp") -}}{{- $_ := set $anns "policy-sets/build.timestamp" ($root.Values.build.timestamp | toString) -}}{{- end -}}
	{{- end -}}
	{{- if and ($root.Values.build) ($root.Values.build.integritySha256) (ne ($root.Values.build.integritySha256 | toString) "") -}}
		{{- if not (hasKey $anns "policy-sets/build.integrity.sha256") -}}{{- $_ := set $anns "policy-sets/build.integrity.sha256" ($root.Values.build.integritySha256 | toString) -}}{{- end -}}
	{{- end -}}
	{{- $_ := set $doc "metadata" $meta -}}
	{{- $finalName := (get (get $doc "metadata" | default (dict)) "name" | default "") -}}
	{{- if and (ne $finalName "-") (ne $finalName "") -}}{{ toYaml $doc }}{{- end -}}
{{- end -}}
{{- end -}}

{{/* Gatekeeper iteration loop; emits docs only when render produced output */}}
{{- define "policy-sets.gk.loop" -}}
{{- $glob := .glob -}}
{{- $pol := .pol | default (dict) -}}
{{- $root := .root -}}
{{- /* Combined profile inclusion: collect auto-enabled set & layered overrides (later profiles override earlier) */ -}}
{{- $auto := dict -}}
{{- $profileOverrides := dict -}}
{{- range $p := ($root.Values.activeProfiles | default (list)) -}}
	{{- $pdef := (get ($root.Values.profiles | default dict) $p) -}}
	{{- if $pdef -}}
		{{- /* policies list -> auto-enabled */ -}}
		{{- range $k := (get $pdef "policies" | default list) -}}
			{{- if not (hasKey $auto $k) -}}{{- $_ := set $auto $k true -}}{{- end -}}
			{{- /* For Gatekeeper also register underscore variant for backward compat */ -}}
			{{- $underscore := replace $k "-" "_" -}}
			{{- if not (hasKey $auto $underscore) -}}{{- $_ := set $auto $underscore true -}}{{- end -}}
		{{- end -}}
		{{- /* overrides map: key -> partial config (enabled optional) */ -}}
		{{- $ov := (get $pdef "overrides" | default dict) -}}
		{{- range $ok, $ovv := $ov -}}
			{{- $existing := (get $profileOverrides $ok) | default (dict) -}}
			{{- /* Merge (later profiles override earlier) */ -}}
			{{- range $k2, $v2 := $ovv -}}{{- $_ := set $existing $k2 $v2 -}}{{- end -}}
			{{- $_ := set $profileOverrides $ok $existing -}}
		{{- end -}}
	{{- end -}}
{{- end -}}
{{- range $path, $bytes := ($root.Files.Glob $glob) -}}
	{{- $name := trimSuffix ".yaml" (base $path) -}}
	{{- $underscore := replace "-" "_" $name -}}
	{{- $cfg := dict -}}
	{{- $deprecated := false -}}
	{{- if $pol -}}
		{{- if hasKey $pol $name -}}
			{{- $cfg = get $pol $name -}}
		{{- else if hasKey $pol $underscore -}}
			{{- $cfg = get $pol $underscore -}}
			{{- $deprecated = true -}}
		{{- end -}}
	{{- end -}}
	{{- $enabled := true -}}
	{{- if and (not $cfg) (hasKey $auto $name) -}}
	  {{- /* auto-enable from profile: start with profile override if present */ -}}
	  {{- $pcfg := (get $profileOverrides $name) | default (dict) -}}
	  {{- if not (hasKey $pcfg "enabled") -}}{{- $_ := set $pcfg "enabled" true -}}{{- end -}}
	  {{- $cfg = $pcfg -}}
	{{- else if and (not $cfg) (hasKey $auto $underscore) -}}
	  {{- $pcfg := (get $profileOverrides $underscore) | default (dict) -}}
	  {{- if not (hasKey $pcfg "enabled") -}}{{- $_ := set $pcfg "enabled" true -}}{{- end -}}
	  {{- $cfg = $pcfg -}}
	{{- else if and $cfg (hasKey $profileOverrides $name) -}}
	  {{- /* Merge profile override into explicit cfg without overwriting explicit enabled flag */ -}}
	  {{- $ovr := (get $profileOverrides $name) -}}
	  {{- range $k3, $v3 := $ovr -}}
	    {{- if or (not (hasKey $cfg $k3)) (and (ne $k3 "enabled")) -}}{{- $_ := set $cfg $k3 $v3 -}}{{- end -}}
	  {{- end -}}
	{{- end -}}
	{{- if and $cfg (hasKey $cfg "enabled") -}}{{- $enabled = get $cfg "enabled" -}}{{- end -}}
	{{- if $enabled -}}
		{{- $rendered := include "policy-sets.gk.render" (dict "bytes" $bytes "root" $root) -}}
		{{- if $rendered -}}
			{{- if $deprecated }}# Deprecated policy key used: {{ $underscore }} (use {{ $name }}){{- end }}
{{ printf "\n---\n" }}{{- $rendered -}}{{ printf "\n" }}
		{{- end -}}
	{{- end -}}
{{- end -}}
{{- end -}}

{{/* Kyverno iteration loop; mirrors gatekeeper loop but for kyverno policies */}}
{{- define "policy-sets.kyverno.loop" -}}
{{- $root := .root -}}
{{- $pol := $root.Values.kyverno.policies | default (dict) -}}
{{- if $root.Values.kyverno.useProfilesOnly -}}
	{{- /* Ignore base policies map when forcing profile-only render */ -}}
	{{- $pol = dict -}}
{{- end -}}
{{- $defaultAction := ($root.Values.kyverno.validationFailureAction | default "") -}}
{{- /* Combined profile inclusion (auto-enable + layered overrides) */ -}}
{{- $auto := dict -}}
{{- $profileOverrides := dict -}}
{{- range $p := ($root.Values.activeProfiles | default list) -}}
	{{- $pdef := (get ($root.Values.profiles | default dict) $p) -}}
	{{- if $pdef -}}
		{{- range $k := (get $pdef "policies" | default list) -}}
			{{- $k1 := $k -}}
			{{- $k2 := $k -}}
			{{- if not (hasSuffix "-policy" $k1) -}}{{- $k2 = printf "%s-policy" $k1 -}}{{- end -}}
			{{- if not (hasKey $auto $k1) -}}{{- $_ := set $auto $k1 true -}}{{- end -}}
			{{- if not (hasKey $auto $k2) -}}{{- $_ := set $auto $k2 true -}}{{- end -}}
		{{- end -}}
		{{- $ov := (get $pdef "overrides" | default dict) -}}
		{{- range $ok, $ovv := $ov -}}
			{{- $existing := (get $profileOverrides $ok) | default (dict) -}}
			{{- range $k3, $v3 := $ovv -}}{{- $_ := set $existing $k3 $v3 -}}{{- end -}}
			{{- $_ := set $profileOverrides $ok $existing -}}
		{{- end -}}
	{{- end -}}
{{- end -}}
{{- range $path, $bytes := ($root.Files.Glob "files/kyverno/*.yaml") -}}
	{{- $name := trimSuffix ".yaml" (base $path) -}}
	{{- $cfg := (get $pol $name) | default (dict) -}}
	{{- $enabled := false -}}
	{{- if and $cfg (hasKey $cfg "enabled") -}}
		{{- $enabled = get $cfg "enabled" -}}
	{{- else if hasKey $auto $name -}}
		{{- $enabled = true -}}
		{{- if hasKey $profileOverrides $name -}}
			{{- $ovr := (get $profileOverrides $name) -}}
			{{- range $k4, $v4 := $ovr -}}
				{{- if not (hasKey $cfg $k4) -}}{{- $_ := set $cfg $k4 $v4 -}}{{- end -}}
			{{- end -}}
		{{- end -}}
	{{- end -}}
	{{- /* Merge per-policy override (layered) if explicit cfg and profile override present (do not override explicit enabled flag) */ -}}
	{{- if and $enabled (hasKey $profileOverrides $name) -}}
		{{- $ovr := (get $profileOverrides $name) -}}
		{{- range $k5, $v5 := $ovr -}}
			{{- if or (not (hasKey $cfg $k5)) (and (ne $k5 "enabled")) -}}{{- $_ := set $cfg $k5 $v5 -}}{{- end -}}
		{{- end -}}
	{{- end -}}
	{{- if $enabled -}}
		{{- $action := (get $cfg "validationFailureAction" | default $defaultAction) -}}
		{{- $r := include "policy-sets.kyverno.render" (dict "bytes" $bytes "action" $action "name" $name "root" $root) -}}
		{{- if $r -}}
{{ printf "\n---\n" }}{{- $r -}}{{ printf "\n" }}
		{{- end -}}
	{{- end -}}
{{- end -}}
{{- end -}}
