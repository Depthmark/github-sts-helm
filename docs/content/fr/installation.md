---
title: Installation
description: Installez depuis le paquet OCI, configurez plusieurs GitHub Apps, tirez depuis un registre privé et épinglez l'image par digest.
weight: 2
translationKey: helm-chart-installation
translationStatus: pending-review
---

Chaque scénario ci-dessous suppose les prérequis du [Démarrage rapide]({{< relref "quickstart" >}}) : un namespace, une GitHub App enregistrée et sa clé privée stockée dans un Secret Kubernetes que vous avez créé.

## Installer depuis le paquet OCI

Le chart est publié comme artefact OCI. Il n'y a pas de dépôt de charts à ajouter, ni d'étape `helm repo update`.

```bash
helm install github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --namespace github-sts --create-namespace \
  --version 0.0.3 \
  --values values.yaml
```

Chaque version publiée est signée avec [cosign](https://docs.sigstore.dev/cosign/overview/) et accompagnée d'une attestation de provenance de build. Vérifiez les deux avant d'installer sur un cluster de production :

```bash
cosign verify ghcr.io/depthmark/charts/github-sts:0.0.3 \
  --certificate-identity-regexp '^https://github\.com/Depthmark/github-sts-helm/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

gh attestation verify oci://ghcr.io/depthmark/charts/github-sts:0.0.3 \
  --repo Depthmark/github-sts-helm
```

Pour inspecter une version sans l'installer :

```bash
helm show values oci://ghcr.io/depthmark/charts/github-sts --version 0.0.3
helm template github-sts oci://ghcr.io/depthmark/charts/github-sts --version 0.0.3 --values values.yaml
```

## Configurer plusieurs GitHub Apps

Un même déploiement peut servir plusieurs GitHub Apps. Chaque entrée sous `github.apps` a besoin de son propre App ID et de son propre Secret, puisque chaque App a sa propre clé privée.

```bash
kubectl create secret generic github-sts-ci-app \
  --namespace github-sts \
  --from-file=github-app-private-key=./ci-app.private-key.pem

kubectl create secret generic github-sts-release-app \
  --namespace github-sts \
  --from-file=github-app-private-key=./release-app.private-key.pem
```

```yaml
github:
  apps:
    ci:
      appId: "123456"
      existingSecret: github-sts-ci-app
    release:
      appId: "654321"
      existingSecret: github-sts-release-app
      orgPolicyRepo: .github
```

Le chart monte chaque clé sur `/etc/github-sts/apps/{app}/{key}` et écrit le `private_key_path` correspondant dans le ConfigMap. Rien n'est partagé entre les apps : un client qui demande `app=ci` ne peut jamais être signé par la clé de l'App `release`.

Le nom de l'app fait partie du chemin de la politique de confiance. Avec les valeurs ci-dessus, un client envoyant `app=release&identity=deploy` résout la politique `.github/sts/release/deploy.sts.yaml` dans le dépôt cible. `orgPolicyRepo` permet à l'App `release` de se rabattre sur une politique stockée centralement dans le dépôt `.github` de l'organisation ; voir [Politiques de confiance]({{< relref "/concepts/trust-policies" >}}) pour l'ordre de résolution.

### Nommer la clé dans le Secret

`secretPrivateKeyKey` remplace le nom de clé par défaut, ce qui est utile lorsque le Secret est géré par un opérateur de secrets externes qui impose sa propre organisation.

```yaml
github:
  apps:
    ci:
      appId: "123456"
      existingSecret: github-sts-ci-app
      secretPrivateKeyKey: tls.key
```

Le chart ne projette que cette clé dans le pod. Les autres clés du même Secret ne sont pas montées.

## Tirer depuis un registre privé

Répliquez l'image et pointez le chart vers votre registre :

```yaml
image:
  registry: registry.internal.example.com
  repository: platform/github-sts

imagePullSecrets:
  - name: internal-registry
```

`image.registry` et `image.repository` sont concaténés : l'exemple ci-dessus tire `registry.internal.example.com/platform/github-sts`.

## Épingler l'image par digest

`image.tag` vaut par défaut l'`appVersion` du chart. Un tag est un pointeur mutable : quiconque peut pousser sur le registre peut le déplacer. `image.digest` ne l'est pas.

```bash
crane digest ghcr.io/depthmark/github-sts:0.0.3
```

```yaml
image:
  digest: sha256:3f79bb7b435b05321651daefd374cdc681dc06faa65e374e38337b88ca046dea
```

Lorsque `digest` est renseigné, le chart génère `repository@digest` et ignore complètement `tag`. Épinglez par digest sur tout cluster qui vérifie les images à l'admission — cosign, Kyverno `verifyImages` ou Sigstore policy-controller — car ces politiques attestent d'un digest, pas d'un tag.

## Charger un bundle de politiques signé

`bundles` ajoute une couche Rego qui s'exécute après que la politique de confiance YAML a autorisé la requête et avant l'émission d'un jeton d'installation. Chaque entrée est écrite directement dans la configuration du serveur : les champs portent donc les noms snake_case du serveur, et non le camelCase du chart.

La gestion des bundles est plus récente que la version du serveur épinglée par l'`appVersion` de ce chart. Procédez dans cet ordre.

### 1. Faire tourner une image qui gère les bundles

La version `v0.0.3` du serveur ignore la clé `bundles:` au lieu de la rejeter. Le pod démarre, les échanges aboutissent, et aucun Rego ne s'exécute. Ni le chart ni le pod ne le signalent : commencez donc par basculer l'image vers une version qui gère les bundles, via `image.tag` ou `image.digest` comme ci-dessus.

La page [Compatibilité]({{< relref "/integrations/compatibility" >}}) liste les combinaisons vérifiées de serveur, de chart et d'Action.

### 2. Définir le mode d'application

Une image qui gère les bundles exige une clé `bundle_enforcement` de premier niveau, valant `required` ou `optional`, et refuse de démarrer sans elle. Le chart ne génère pas cette clé : définissez-la par l'environnement.

```yaml
extraEnv:
  - name: GITHUBSTS_BUNDLE_ENFORCEMENT
    value: required
```

`required` est la posture de production. `optional` laisse le serveur fonctionner sans aucun bundle installé, et il l'annonce par un avertissement au démarrage ainsi que dans sa santé, ses métriques et son audit.

### 3. Configurer le bundle

```yaml
bundles:
  - name: enterprise-baseline
    apps: []
    ref: oci://ghcr.io/example/github-sts-policy@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
    expected_policy_revision: "42"
    poll_interval: 5m
    max_staleness: 10m
    fail_mode: closed
    cosign:
      certificate_identity_regexp: '^https://github\.com/example/github-sts-policy/\.github/workflows/release\.yml@refs/heads/main$'
      certificate_oidc_issuer: https://token.actions.githubusercontent.com
```

C'est le serveur qui récupère le bundle, à l'exécution. `imagePullSecrets` ne concerne que le kubelet tirant l'image du conteneur et n'a aucun effet ici, et une NetworkPolicy qui autorise la sortie vers l'API GitHub n'autorise pas la sortie vers un registre de bundles. La page [Réseau]({{< relref "networking" >}}) traite ce volet.

Le mode `required` contraint la forme d'une entrée, notamment l'épinglage par digest et la révision signée qu'elle doit déclarer. La page [Configuration]({{< relref "/reference/configuration" >}}) fait référence sur ces règles.

### Monter un fichier attendu par une entrée de bundle

Le chart ne monte rien pour le compte d'un bundle. Un `ref` de fichier local, un `registry.auth.password_file` et un `cosign.public_key_ref` désignent chacun un chemin à l'intérieur du conteneur : le fichier doit donc arriver via `extraVolumes` et `extraVolumeMounts`.

```bash
kubectl create secret generic github-sts-bundle \
  --namespace github-sts \
  --from-literal=registry-password=ghs_xxxxxxxxxxxxxxxxxxxx \
  --from-file=cosign.pub=./cosign.pub
```

```yaml
extraVolumes:
  - name: bundle
    secret:
      secretName: github-sts-bundle

extraVolumeMounts:
  - name: bundle
    mountPath: /var/run/secrets/bundle
    readOnly: true

bundles:
  - name: enterprise-baseline
    apps: []
    ref: oci://registry.internal.example.com/policy/github-sts@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
    expected_policy_revision: "42"
    fail_mode: closed
    registry:
      auth:
        mode: basic
        username: robot$github-sts
        password_file: /var/run/secrets/bundle/registry-password
    cosign:
      public_key_ref: /var/run/secrets/bundle/cosign.pub
```

L'authentification au registre et la vérification cosign restent distinctes. L'identifiant détermine si le pod peut récupérer le bundle. Les champs cosign déterminent si le bundle récupéré est digne de confiance.

### Vérifier

Générez le ConfigMap pour voir ce que le serveur lira :

```bash
helm template github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --version 0.0.3 --values values.yaml \
  --show-only templates/configmap.yaml
```

Chaque champ renseigné apparaît dans le bloc généré, les clés de chaque entrée étant triées par ordre alphabétique. Le chart ne valide pas les entrées : un champ mal orthographié parvient donc au serveur inchangé et échoue là, et non au rendu.

## Installer sans CRD supplémentaires

Chaque objet optionnel du chart dépend d'un groupe d'API qui peut ne pas être installé :

| Valeur | Nécessite |
|---|---|
| `httproute.enabled` | Les CRD Gateway API (`gateway.networking.k8s.io`) |
| `networkPolicy.cilium.enabled` | Les CRD Cilium (`cilium.io/v2`) |
| `serviceMonitor.enabled`, `podMonitor.enabled` | Les CRD Prometheus Operator (`monitoring.coreos.com/v1`) |

Ces quatre valeurs sont à `false` par défaut : une installation par défaut n'exige aucune CRD au-delà de Kubernetes lui-même. En activer une dont la CRD est absente fait échouer `helm install` à l'application, avec `no matches for kind`.

## Vérifier un changement avant de l'appliquer

`helm template` effectue le rendu localement, sans contacter le cluster, ce qui en fait le moyen le moins coûteux de relire un changement de valeurs :

```bash
helm template github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --version 0.0.3 --values values.yaml \
  | kubectl diff --namespace github-sts -f -
```

## Désinstaller

```bash
helm uninstall github-sts --namespace github-sts
```

Helm supprime tout ce qu'il a créé. Les Secrets de clé privée subsistent, car le chart ne les a jamais possédés. Supprimez-les séparément lorsque vous démantelez définitivement le déploiement.

## Suite

- [Réseau]({{< relref "networking" >}}) pour exposer le Service et restreindre sa sortie réseau
- [Référence des valeurs]({{< relref "values" >}}) pour toutes les valeurs acceptées par le chart
- [Ressources générées]({{< relref "resources" >}}) pour ce que produit chaque template
