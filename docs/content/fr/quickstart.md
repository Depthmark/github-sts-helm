---
title: Démarrage rapide
description: Installez le chart dans un namespace vide avec une GitHub App, puis vérifiez que le serveur est prêt à échanger des jetons.
weight: 1
translationKey: helm-chart-quickstart
translationStatus: pending-review
---

Cette page part d'un namespace Kubernetes vide et vous laisse avec un serveur github-sts en fonctionnement, capable d'émettre des jetons d'installation pour une GitHub App.

**Public :** une personne qui exploite un cluster et dispose de `helm` et `kubectl` sur un namespace.

**Objectif :** un déploiement `Ready` qui répond sur `/ready` et passe `helm test`.

## Prérequis

1. Kubernetes 1.19 ou plus récent, et Helm 3.
2. Une GitHub App enregistrée et installée sur les dépôts que vous comptez cibler. Voir [Configurer la GitHub App]({{< relref "/get-started/configure-github-app" >}}).
3. La clé privée de l'App sous forme de fichier PEM sur votre poste.

Le chart ne crée pas de Secret pour la clé privée, et aucune valeur du chart n'accepte de matériel cryptographique. Vous créez le Secret ; le chart le monte en lecture seule.

## Étapes

### 1. Créer le namespace et le Secret de clé privée

```bash
kubectl create namespace github-sts

kubectl create secret generic github-sts-default-app \
  --namespace github-sts \
  --from-file=github-app-private-key=./default-app.private-key.pem
```

La clé à l'intérieur du Secret doit s'appeler `github-app-private-key`, sinon vous devez la nommer explicitement avec `github.apps.<name>.secretPrivateKeyKey`.

### 2. Écrire un fichier de valeurs

```yaml
# values.yaml
github:
  apps:
    default:
      appId: "123456"
      existingSecret: github-sts-default-app

oidc:
  allowedIssuers:
    - https://token.actions.githubusercontent.com
  requiredAudience: https://sts.example.com

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

La clé de la map sous `github.apps` est le nom de l'app. Ce n'est pas cosmétique : elle sélectionne le répertoire depuis lequel une politique de confiance est lue, `.github/sts/{app}/{identity}.sts.yaml`, et c'est ce qu'un client envoie comme paramètre `app`.

`oidc.requiredAudience` est un plancher applicable à tout le serveur sur la revendication `aud`, vérifié avant tout chargement de politique. Renseignez-y l'URL publique de ce déploiement, afin qu'un fichier de politique trop permissif ne puisse pas accepter un jeton émis pour une autre partie de confiance.

### 3. Installer le chart

```bash
helm install github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --namespace github-sts \
  --version 0.0.3 \
  --values values.yaml
```

Passez toujours `--version`. Sans ce drapeau, Helm résout le chart publié le plus récent, ce qui fait dépendre la version déployée du moment où la commande a été lancée.

## Résultat attendu

Deux réplicas atteignent l'état `Running`, car `replicaCount` vaut `2` par défaut :

```bash
kubectl get pods --namespace github-sts
```

```text
NAME                          READY   STATUS    RESTARTS   AGE
github-sts-6d4f8b9c7d-4nzq2   1/1     Running   0          40s
github-sts-6d4f8b9c7d-x8k5m   1/1     Running   0          40s
```

Les notes de release affichent la commande de port-forward pour le Service `ClusterIP` par défaut, et avertissent si `github.apps` est vide.

## Vérification

Lancez les tests du chart. Ils créent des Pods éphémères qui interrogent le serveur depuis l'intérieur du cluster, puis sont supprimés.

```bash
helm test github-sts --namespace github-sts
```

Les tests vérifient que `/health` retourne `{"status":"ok"}`, que `/ready` retourne HTTP 200 et — lorsque `metrics.enabled` est vrai, ce qui est le cas par défaut — que `/metrics` sert des métriques Prometheus.

Inspectez la configuration générée par le chart, c'est-à-dire le fichier que le serveur lit réellement :

```bash
kubectl get configmap github-sts-config --namespace github-sts -o jsonpath='{.data.config\.yaml}'
```

Confirmez que la clé privée est montée là où la configuration l'attend :

```bash
kubectl exec --namespace github-sts deploy/github-sts -- \
  ls /etc/github-sts/apps/default
```

## Limites

- Le chart configure le serveur mais ne contacte jamais GitHub lui-même. Un `appId` erroné, une App non installée ou une politique de confiance absente se manifestent au premier échange, pas à l'installation.
- `/ready` rend compte de l'état du processus. Il ne prouve ni que GitHub est joignable ni qu'un point d'entrée JWKS se résout. Les problèmes de sortie réseau apparaissent sous forme d'échanges en échec et dans la métrique de joignabilité.
- Aucun Ingress ni HTTPRoute n'est créé par défaut. Tant que vous n'en activez pas un, le Service n'est joignable que depuis l'intérieur du cluster.

## Suite

- [Installation]({{< relref "installation" >}}) pour plusieurs GitHub Apps, les registres privés et l'épinglage par digest
- [Réseau]({{< relref "networking" >}}) pour exposer le Service et restreindre sa sortie réseau
- [Référence des valeurs]({{< relref "values" >}}) pour la surface de configuration complète
