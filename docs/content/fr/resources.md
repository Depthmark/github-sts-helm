---
title: Ressources générées
description: Chaque objet Kubernetes produit par le chart, la valeur qui le conditionne et le groupe d'API dont il dépend.
weight: 4
translationKey: helm-chart-resources
translationStatus: pending-review
---

Cette page associe chaque template du chart à l'objet qu'il produit. Elle est vérifiée contre `charts/github-sts/templates` à chaque pull request : un template qui existe est listé ici.

Effectuez vous-même le rendu pour n'importe quel fichier de valeurs avant de l'appliquer :

```bash
helm template github-sts charts/github-sts --values values.yaml
```

## Toujours générés

<!-- resources:begin -->

| Template | Type | Notes |
|---|---|---|
| `deployment.yaml` | Deployment `apps/v1` | Le serveur. Porte une annotation de pod `checksum/config` : tout changement de la configuration générée fait rouler les pods au lieu de les laisser sur une configuration périmée. |
| `configmap.yaml` | ConfigMap `v1` | La configuration du serveur, montée en lecture seule sur `/etc/github-sts/config.yaml` et localisée par la variable d'environnement `GITHUBSTS_CONFIG_PATH`. Nommé `{fullname}-config`. |
| `service.yaml` | Service `v1` | Expose les pods sur `service.port`, en ciblant le port nommé du conteneur. Ce nom vaut `http`, ou `https` avec `appProtocol: https` lorsque `tls.enabled` est actif. |
| `secret.yaml` | aucun | Ne produit rien. Ce fichier est un marqueur consignant que le chart ne crée délibérément aucun Secret : chaque clé privée de GitHub App provient d'un `existingSecret` dont vous êtes propriétaire. |

## Générés sous condition

| Template | Type | Généré lorsque |
|---|---|---|
| `serviceaccount.yaml` | ServiceAccount `v1` | `serviceAccount.create` est vrai. Renseignez `serviceAccount.name` et désactivez `create` pour réutiliser un compte existant. |
| `poddisruptionbudget.yaml` | PodDisruptionBudget `policy/v1` | `pdb.enabled` est vrai, ce qui est le cas par défaut. Utilise `minAvailable`, ou `maxUnavailable` si seul celui-ci est renseigné, et retombe sur `minAvailable: 1`. |
| `hpa.yaml` | HorizontalPodAutoscaler `autoscaling/v2` | `autoscaling.enabled` est vrai. Le Deployment omet alors `replicas`, et `replicaCount` ne s'applique plus. |
| `ingress.yaml` | Ingress `networking.k8s.io/v1` | `ingress.enabled` est vrai. |
| `httproute.yaml` | HTTPRoute `gateway.networking.k8s.io/v1` | `httproute.enabled` est vrai. Exige les CRD Gateway API. |
| `networkpolicy.yaml` | NetworkPolicy `networking.k8s.io/v1` | `networkPolicy.native.enabled` est vrai. |
| `ciliumnetworkpolicy.yaml` | CiliumNetworkPolicy `cilium.io/v2` | `networkPolicy.cilium.enabled` est vrai. Exige la CRD Cilium. |
| `servicemonitor.yaml` | ServiceMonitor `monitoring.coreos.com/v1` | `serviceMonitor.enabled` est vrai. Exige les CRD Prometheus Operator. Collecte avec `scheme: https` lorsque `tls.enabled` est actif. |
| `podmonitor.yaml` | PodMonitor `monitoring.coreos.com/v1` | `podMonitor.enabled` est vrai. Exige les CRD Prometheus Operator. Collecte avec `scheme: https` lorsque `tls.enabled` est actif. |

## Tests

Ce sont des Pods annotés `helm.sh/hook: test`. Ils sont créés par `helm test`, pas par `helm install`, et sont supprimés en cas de succès ainsi qu'avant l'exécution suivante. Tous trois exécutent `tests.image` et suivent `tls.enabled`, en interrogeant l'endpoint en HTTPS sans vérifier le certificat. Aucun n'est généré lorsque `tests.enabled` est faux, ni lorsque `tls.clientAuth.enabled` est actif, car un Pod de hook n'a aucun certificat client à présenter.

| Template | Pod | Vérifie |
|---|---|---|
| `tests/test-connection.yaml` | `{fullname}-test-health` | `/health` retourne HTTP 200 avec `{"status":"ok"}`. |
| `tests/test-readiness.yaml` | `{fullname}-test-ready` | `/ready` retourne HTTP 200. |
| `tests/test-metrics.yaml` | `{fullname}-test-metrics` | `/metrics` sert des métriques Prometheus. Généré uniquement lorsque `metrics.enabled` est vrai. |

<!-- resources:end -->

Une NetworkPolicy qui refuse l'entrée interne au cluster refuse aussi les Pods de test. Ajoutez leur namespace à `networkPolicy.native.from` ou `networkPolicy.cilium.fromEndpoints` si vous voulez que `helm test` continue de fonctionner sous une politique.

## Le pod

Le Deployment produit un conteneur unique dont la forme est fixe.

| Montage | Source | Raison |
|---|---|---|
| `/etc/github-sts` | ConfigMap, lecture seule | Le fichier de configuration du serveur. |
| `/etc/github-sts/apps/{app}` | Secret, lecture seule | Un montage par entrée de `github.apps`, projetant uniquement la clé privée configurée. |
| `tls.mountPath` | Secret projeté, lecture seule | Généré uniquement lorsque `tls.enabled` est vrai. Projette le certificat de service et sa clé, plus le bundle de CA clientes sous `clientAuth`, depuis un ou deux Secrets vers un montage unique. Vaut `/etc/github-sts-tls` par défaut : un répertoire distinct plutôt qu'un chemin sous le montage de configuration ci-dessus. |
| `/tmp` | `emptyDir` | Le système de fichiers racine étant en lecture seule, l'espace de travail doit être un volume. |
| Parent de `audit.filePath` | `emptyDir`, 100 Mio | Généré uniquement lorsque `audit.fileEnabled` est vrai. Supprimé avec le pod : exportez le flux hors du nœud s'il doit survivre. |

Le conteneur écoute sur `service.targetPort` sous le port nommé `http`, ou `https` lorsque `tls.enabled` est actif, et sert :

| Chemin | Utilisé par |
|---|---|
| `/sts/exchange` | Les clients qui échangent un jeton OIDC. |
| `/health` | La sonde de vivacité et le test `test-health`. |
| `/ready` | Les sondes de disponibilité et de démarrage, ainsi que le test `test-ready`. |
| `/metrics` | Prometheus, les moniteurs et le test `test-metrics`. Généré uniquement lorsque `metrics.enabled` est vrai. |

Sous `tls.clientAuth.enabled`, le kubelet n'utilise plus ces chemins : les sondes deviennent des vérifications `tcpSocket` sur le même port, faute de pouvoir présenter un certificat client. Voir [TLS et mTLS]({{< relref "tls" >}}).

## Labels

Chaque objet porte les labels recommandés standard — `app.kubernetes.io/name`, `instance`, `version`, `managed-by` et `helm.sh/chart` — ainsi que le contenu de `commonLabels`. Les labels de sélecteur se limitent à `name` et `instance` : ajouter une entrée dans `commonLabels` ne modifie donc pas le sélecteur et n'orpheline pas les pods en cours d'exécution.

## Suite

- [Référence des valeurs]({{< relref "values" >}}) pour les valeurs qui conditionnent ces objets
- [Réseau]({{< relref "networking" >}}) pour les objets de routage et de politique en contexte
- [TLS et mTLS]({{< relref "tls" >}}) pour les montages et les ports que modifient les valeurs `tls`
- [Mise à niveau]({{< relref "upgrade" >}}) pour la façon dont un changement de ces objets est déployé
