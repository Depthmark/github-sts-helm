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

`policyResolution` détermine quel côté l'emporte lorsque les deux dépôts déclarent la même identité. Sa valeur par défaut est `org_first` : la copie de l'organisation est lue en premier et le dépôt à l'origine de la requête ne sert que de repli. Utilisez `org_only` pour ne plus lire du tout le dépôt à l'origine de la requête, ou `repo_first` pour l'ordre historique, qui laisse un dépôt contourner la politique centrale :

```yaml
github:
  apps:
    release:
      appId: "654321"
      existingSecret: github-sts-release-app
      orgPolicyRepo: .github
      policyResolution: org_only
```

Le mode n'a de sens qu'avec `orgPolicyRepo` : le chart refuse donc `org_first` et `org_only` en son absence, plutôt que de laisser le serveur rejeter la configuration une fois la mise à jour réussie. [Référence des valeurs]({{< relref "values" >}}) documente les trois modes.

### Regrouper plusieurs GitHub Apps sous un seul nom

Plusieurs GitHub Apps peuvent être adossées à un seul nom d'app. Chacune dispose de son propre quota de limitation de débit principal : le plafond d'échanges pour ce nom augmente donc avec le nombre d'instances, et le serveur bascule vers une autre instance lorsque celle qu'il a essayée est limitée ou injoignable. Les clients ne changent rien : ils continuent d'envoyer le seul nom dans `app=`.

```bash
kubectl create secret generic github-sts-checkout-1 \
  --namespace github-sts \
  --from-file=github-app-private-key=./checkout-1.private-key.pem

kubectl create secret generic github-sts-checkout-2 \
  --namespace github-sts \
  --from-file=github-app-private-key=./checkout-2.private-key.pem
```

```yaml
github:
  apps:
    checkout:
      orgPolicyRepo: .github
      instances:
        - name: checkout-1
          appId: "111111"
          existingSecret: github-sts-checkout-1
        - name: checkout-2
          appId: "222222"
          existingSecret: github-sts-checkout-2
```

`instances` et `appId` sont exclusifs sur une même entrée, et le chart échoue au rendu plutôt que de laisser une entrée ambiguë atteindre le cluster. Les clés arrivent sur `/etc/github-sts/apps/checkout/{appId}/{key}`, un sous-répertoire par instance, projetées depuis le Secret propre à chaque instance vers le montage unique que l'app possède déjà.

Enregistrez chaque instance comme une GitHub App distincte et installez-les toutes avec les mêmes permissions et le même accès aux dépôts. Le serveur choisit librement entre elles et ne vérifie pas qu'elles correspondent : une instance installée sur moins de dépôts produit des réponses `422` sur la part des requêtes qu'elle sert.

Cette forme exige une image serveur qui comprend `apps.<name>.instances`, soit github-sts 0.1.1 ou ultérieure, ce que l'`appVersion` de ce chart épingle déjà. Une image plus ancienne rejette la clé et le pod redémarre en boucle avec `field instances not found in type config.AppConfig`. Consultez [Compatibilité]({{< relref "/integrations/compatibility" >}}) avant de convertir une entrée, et [Configuration]({{< relref "/reference/configuration" >}}) pour les règles de sélection et de bascule, y compris `rotation`.

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

## Conserver les clés d'App dans Azure Key Vault

Avec un `signer`, la clé privée de l'App reste dans Azure Key Vault et github-sts ne reçoit que des signatures du JWT de l'App. Aucun Secret ne contient la clé, et le chart n'en monte aucune dans le pod. Cela exige github-sts 0.1.3 ou ultérieure.

### 1. Préparer le coffre et les identités

Importez le PEM de chaque App dans le coffre comme clé limitée à `sign`, puis supprimez le fichier. Créez une identité managée affectée par l'utilisateur par coffre, ou une seule pour tous, et accordez à chacune la permission `sign` sur ses propres clés et rien d'autre ; laissez le pare-feu du coffre admettre l'adresse depuis laquelle le pod appelle. [Configuration]({{< relref "/reference/configuration#signer" >}}) donne la commande d'import et le rôle le plus restreint.

Ajoutez à chaque identité un identifiant fédéré qui nomme l'émetteur de comptes de service de ce cluster, l'audience `api://AzureADTokenExchange`, et le ServiceAccount du pod comme subject. Pour une release nommée `github-sts` dans le namespace `github-sts`, avec le ServiceAccount du chart, c'est `system:serviceaccount:github-sts:github-sts`. Plusieurs identités peuvent faire confiance au même ServiceAccount. Entra ID récupère le document de découverte et les clés de l'émetteur : celui-ci doit être joignable depuis Internet.

### 2. Pointer les apps vers leurs clés

```yaml
cloudIdentities:
  vault-one:
    azure:
      clientId: 00000000-0000-0000-0000-000000000001
      tenantId: 00000000-0000-0000-0000-000000000003

github:
  apps:
    ci:
      appId: "123456"
      signer:
        cloudIdentity: vault-one
        keyId: https://myvault.vault.azure.net/keys/github-app-ci
    release:
      appId: "654321"
      signer:
        cloudIdentity: vault-one
        keyId: https://myvault.vault.azure.net/keys/github-app-release
```

Toutes les apps changent en même temps. Le chart refuse une release dont les apps mélangent `signer` et `existingSecret`, comme le ferait le serveur : il n'y a donc jamais de PEM sur lequel se rabattre. Les instances de pool prennent `signer` de la même façon, à la place de `existingSecret`.

Le chart projette un jeton de ServiceAccount pour l'audience ci-dessus dans `/var/run/secrets/github-sts-azure/token` et définit `AZURE_FEDERATED_TOKEN_FILE` ; les identifiants client et de locataire vont dans le ConfigMap. Il ne compte pas sur le webhook Azure de workload identity, et aucune annotation de compte de service n'est nécessaire. [Référence des valeurs]({{< relref "values#identités-cloud" >}}) couvre plusieurs identités.

### 3. Vérifier

github-sts signe un premier JWT d'App au démarrage et refuse de démarrer quand une clé ne peut pas signer. Un identifiant de clé erroné, un rôle manquant, un pare-feu fermé ou un identifiant fédéré qui ne correspond pas apparaissent tous dans le journal du pod avant qu'il ne reçoive du trafic :

```bash
kubectl logs --namespace github-sts deploy/github-sts
```

Avec une NetworkPolicy, autorisez d'abord la sortie vers le coffre et vers `login.microsoftonline.com` ; [Réseau]({{< relref "networking" >}}) montre comment.

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

La version du serveur épinglée par l'`appVersion` de ce chart gère les bundles. La page [Compatibilité]({{< relref "/integrations/compatibility" >}}) liste les combinaisons vérifiées de serveur, de chart et d'Action.

### 1. Définir le mode d'application

`bundleEnforcement` est écrit dans toute configuration générée, car le serveur refuse de démarrer sans cette clé. Sa valeur par défaut est `optional`.

```yaml
bundleEnforcement: required
```

`required` est la posture de production : le serveur refuse de démarrer tant qu'aucun bundle n'est configuré, si bien que supprimer la liste `bundles` casse le déploiement au lieu d'en retirer silencieusement la couche Rego. `optional` laisse le serveur fonctionner sans aucun bundle installé, et il l'annonce par un avertissement au démarrage ainsi que dans sa santé, ses métriques et son audit.

### 2. Configurer le bundle

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
