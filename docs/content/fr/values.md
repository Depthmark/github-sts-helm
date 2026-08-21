---
title: Référence des valeurs
description: Toutes les valeurs acceptées par le chart github-sts, avec leur valeur par défaut et leur effet sur les manifestes générés.
weight: 3
translationKey: helm-chart-values
translationStatus: pending-review
---

Cette page est le contrat de configuration du chart. Elle est vérifiée contre `charts/github-sts/values.yaml` à chaque pull request : une valeur présente ici existe dans le chart, et une valeur acceptée par le chart figure ici.

Les valeurs qui configurent le *serveur* sont écrites dans le ConfigMap et lues par le processus depuis `/etc/github-sts/config.yaml`. Les valeurs qui configurent le *déploiement* n'affectent que les objets Kubernetes. Les tableaux le précisent lorsque la distinction compte.

<!-- values:begin -->

## GitHub Apps

Obligatoire. Un déploiement sans app configurée démarre, sert `/health` et rejette tous les échanges.

| Valeur | Défaut | Effet |
|---|---|---|
| `github.apps` | `{}` | Map associant un nom d'app à sa configuration. La clé de la map est le nom d'app envoyé par un client dans `app=`, et le répertoire depuis lequel une politique de confiance est lue. Chaque entrée accepte `appId`, `existingSecret`, et facultativement `secretPrivateKeyKey` et `orgPolicyRepo`. |

Chaque entrée accepte les champs suivants :

<!-- values:pause -->

| Champ | Obligatoire | Effet |
|---|---|---|
| `appId` | Oui | Identifiant numérique de la GitHub App. Écrit dans le ConfigMap sous forme d'entier. |
| `existingSecret` | Oui | Nom d'un Secret du namespace de la release contenant la clé privée de l'App. Le chart ne crée jamais ce Secret et aucune valeur n'accepte de matériel cryptographique. |
| `secretPrivateKeyKey` | Non | Clé à l'intérieur de ce Secret. Vaut `github-app-private-key` par défaut. Seule cette clé est projetée dans le pod. |
| `orgPolicyRepo` | Non | Dépôt contenant les politiques de confiance au niveau de l'organisation, typiquement `.github`. Omettez-le pour ne résoudre les politiques que depuis le dépôt cible. |

<!-- values:resume -->

## Identité de la release

| Valeur | Défaut | Effet |
|---|---|---|
| `nameOverride` | `""` | Remplace le nom du chart dans `app.kubernetes.io/name` et dans les noms d'objets générés. |
| `fullnameOverride` | `""` | Remplace purement et simplement le nom d'objet généré. À utiliser lorsque le nom de release produirait un préfixe malcommode. |
| `commonLabels` | `{}` | Labels fusionnés dans chaque objet généré par le chart. Utile pour des labels de propriété ou d'imputation de coûts. |
| `podAnnotations` | `{}` | Annotations ajoutées au template de pod, en plus de l'annotation `checksum/config` déjà posée par le chart. |
| `podLabels` | `{}` | Labels ajoutés au template de pod. Les labels de sélecteur ne sont pas affectés : en ajouter un ici n'orpheline pas les pods en cours d'exécution. |

## Image

| Valeur | Défaut | Effet |
|---|---|---|
| `image.registry` | `"ghcr.io"` | Hôte du registre, concaténé à `repository` par une barre oblique. |
| `image.repository` | `"depthmark/github-sts"` | Chemin de l'image dans le registre. |
| `image.tag` | `""` | Tag de l'image. Vide signifie l'`appVersion` du chart, c'est-à-dire la version contre laquelle le chart a été testé. Ignoré si `digest` est renseigné. |
| `image.digest` | `""` | Digest sous la forme `sha256:<hex>`. Renseigné, le chart génère `repository@digest`, ce dont attestent les vérifications à l'admission par cosign, Kyverno ou policy-controller. Un tag peut être déplacé par quiconque peut pousser ; un digest, non. |
| `image.pullPolicy` | `"IfNotPresent"` | Politique de tirage du kubelet. Avec un tirage par digest, le kubelet considère la référence comme immuable et ne retire pas l'image, quelle que soit cette valeur. |
| `imagePullSecrets` | `[]` | Liste d'entrées `name` pour tirer depuis un registre privé. |

## Charge de travail

| Valeur | Défaut | Effet |
|---|---|---|
| `replicaCount` | `2` | Nombre de réplicas, lorsque `autoscaling.enabled` est faux. La valeur 2 maintient le service pendant le drain d'un nœud. N'utilisez 1 qu'en développement. |
| `revisionHistoryLimit` | `5` | Anciens ReplicaSets conservés pour `kubectl rollout undo`. Chaque changement de configuration fait rouler les pods, puisque le template de pod porte une somme de contrôle du ConfigMap : l'historique s'accumule donc plus vite que dans un chart classique. `0` désactive le retour arrière. |
| `terminationGracePeriodSeconds` | `30` | Secondes entre SIGTERM et SIGKILL. Doit dépasser `server.shutdownTimeout` plus le temps de drain des sondes, sinon les échanges en cours sont coupés pendant une mise à jour progressive. |
| `resources` | `{}` | Demandes et limites du conteneur. Vide signifie sans borne, ce qui place le pod dans la classe de QoS `BestEffort`, première évincée. Renseignez les deux en production. |
| `nodeSelector` | `{}` | Sélecteur de labels de nœuds pour l'ordonnancement. |
| `tolerations` | `[]` | Tolérances aux taints pour l'ordonnancement. |
| `affinity` | `{}` | Règles d'affinité et d'anti-affinité. |
| `topologySpreadConstraints` | `[]` | Contraintes de répartition. À combiner avec un `replicaCount` supérieur à 1 pour éviter que tous les réplicas partagent un nœud ou une zone. |
| `extraEnv` | `[]` | Variables d'environnement supplémentaires du conteneur, au format `EnvVar`. Le chart pose déjà `GITHUBSTS_CONFIG_PATH`. |
| `extraVolumes` | `[]` | Volumes supplémentaires du pod. |
| `extraVolumeMounts` | `[]` | Montages supplémentaires du conteneur. Le système de fichiers racine est en lecture seule : tout chemin où le processus doit écrire exige un volume ici. |

## Disponibilité

| Valeur | Défaut | Effet |
|---|---|---|
| `pdb.enabled` | `true` | Génère un PodDisruptionBudget, pour qu'un drain de nœud ne puisse pas évincer tous les réplicas à la fois. |
| `pdb.minAvailable` | `1` | Réplicas devant rester disponibles pendant une interruption volontaire. Mutuellement exclusif avec `maxUnavailable`. |
| `pdb.maxUnavailable` | `null` | Réplicas pouvant être indisponibles pendant une interruption volontaire. Renseignez celui-ci ou `minAvailable`, jamais les deux. |
| `autoscaling.enabled` | `false` | Génère un HorizontalPodAutoscaler et retire `replicas` du Deployment, confiant le nombre de réplicas au HPA. |
| `autoscaling.minReplicas` | `2` | Borne inférieure du HPA. |
| `autoscaling.maxReplicas` | `10` | Borne supérieure du HPA. |
| `autoscaling.targetCPUUtilizationPercentage` | `80` | Cible d'utilisation CPU. Exige une demande CPU dans `resources`, l'utilisation étant un pourcentage de la demande. |
| `autoscaling.behavior` | `{}` | Bloc `behavior` de `autoscaling/v2`. Permet de ralentir la réduction d'échelle ou de plafonner la montée, afin qu'une rafale d'échanges ne multiplie pas les réplicas plus vite que ne l'autorise la limite de débit de GitHub. |

## Sondes

Les trois sondes interrogent le port HTTP du conteneur. La sonde de vivacité utilise `/health` ; les sondes de disponibilité et de démarrage utilisent `/ready`.

| Valeur | Défaut | Effet |
|---|---|---|
| `probes.mode` | `"auto"` | Transport des sondes. `auto` utilise `httpGet`, en HTTPS lorsque `tls.enabled` est actif, et `tcpSocket` lorsque `tls.clientAuth.enabled` est actif. `httpGet` et `tcpSocket` en imposent un. Une sonde `tcpSocket` prouve seulement que le port accepte les connexions : la forcer masque un serveur qui n'est pas prêt. |
| `probes.startup.enabled` | `false` | Ajoute une sonde de démarrage. Tant qu'elle s'exécute, les sondes de vivacité et de disponibilité sont suspendues, ce qui évite qu'un démarrage à froid lent déclenche une boucle de redémarrage. À activer lorsque la récupération des JWKS ou la restauration d'un grand cache de JTI peut dépasser le budget de vivacité. |
| `probes.startup.initialDelaySeconds` | `0` | Délai avant la première tentative de démarrage. Généralement 0, le seuil fournissant déjà le budget. |
| `probes.startup.periodSeconds` | `5` | Secondes entre deux tentatives de démarrage. |
| `probes.startup.timeoutSeconds` | `3` | Délai maximal par tentative. |
| `probes.startup.failureThreshold` | `30` | Tentatives avant que le kubelet redémarre le conteneur. Le temps de démarrage maximal vaut `failureThreshold * periodSeconds`, soit 150 secondes par défaut. |
| `probes.liveness.enabled` | `true` | Ajoute une sonde de vivacité sur `/health`. Un échec redémarre le conteneur. |
| `probes.liveness.initialDelaySeconds` | `10` | Délai avant la première tentative de vivacité. |
| `probes.liveness.periodSeconds` | `30` | Secondes entre deux tentatives de vivacité. |
| `probes.liveness.timeoutSeconds` | `3` | Délai maximal par tentative. |
| `probes.liveness.failureThreshold` | `3` | Échecs consécutifs avant redémarrage. |
| `probes.readiness.enabled` | `true` | Ajoute une sonde de disponibilité sur `/ready`. Un échec retire le pod des endpoints du Service sans le redémarrer. |
| `probes.readiness.initialDelaySeconds` | `5` | Délai avant la première tentative de disponibilité. |
| `probes.readiness.periodSeconds` | `10` | Secondes entre deux tentatives de disponibilité. |
| `probes.readiness.timeoutSeconds` | `3` | Délai maximal par tentative. |
| `probes.readiness.failureThreshold` | `3` | Échecs consécutifs avant que le pod quitte la liste des endpoints. |

## Contexte de sécurité et identité

Les valeurs par défaut satisfont le profil `restricted` de Pod Security Admission. En affaiblir une est une décision délibérée, pas un réglage de performance.

| Valeur | Défaut | Effet |
|---|---|---|
| `podSecurityContext.runAsNonRoot` | `true` | Refuse de démarrer le pod si l'image se résout à l'UID 0. |
| `podSecurityContext.runAsUser` | `65534` | UID de tous les conteneurs du pod, correspondant à l'image distroless `nonroot`. |
| `podSecurityContext.runAsGroup` | `65534` | GID primaire, pour que le processus n'hérite d'aucune appartenance de groupe issue de l'image. Certaines images non-root livrent malgré tout `gid=0`. |
| `podSecurityContext.fsGroup` | `65534` | Groupe appliqué aux volumes montés. |
| `podSecurityContext.seccompProfile` | `{"type":"RuntimeDefault"}` | Profil seccomp au niveau du pod. |
| `securityContext.allowPrivilegeEscalation` | `false` | Empêche les binaires setuid d'élever leurs privilèges. |
| `securityContext.readOnlyRootFilesystem` | `true` | Rend le système de fichiers racine en lecture seule. Le chart monte des volumes `emptyDir` pour `/tmp` et, si la journalisation d'audit est active, pour le répertoire d'audit. |
| `securityContext.capabilities.drop` | `["ALL"]` | Capacités Linux retirées au conteneur. |
| `securityContext.seccompProfile` | `{"type":"RuntimeDefault"}` | Profil seccomp au niveau du conteneur, prioritaire sur celui du pod. |
| `serviceAccount.create` | `true` | Génère un ServiceAccount dédié plutôt que de réutiliser `default`. |
| `serviceAccount.name` | `""` | Nom du ServiceAccount. Vide signifie le nom d'objet généré si `create` est vrai, et `default` sinon. |
| `serviceAccount.annotations` | `{}` | Annotations du ServiceAccount, par exemple une liaison IRSA ou Workload Identity. |
| `serviceAccount.automountServiceAccountToken` | `false` | Désactivé par défaut : le serveur s'adresse à GitHub, jamais à l'API Kubernetes. Un jeton d'API projeté dans le pod serait donc du matériel d'authentification accessible sans usage légitime. |

## Service et routage

Voir [Réseau]({{< relref "networking" >}}) pour des exemples complets.

| Valeur | Défaut | Effet |
|---|---|---|
| `service.type` | `"ClusterIP"` | Type de Service. |
| `service.port` | `8080` | Port d'écoute du Service. |
| `service.targetPort` | `8080` | Port du conteneur. Également écrit dans le ConfigMap comme port d'écoute du serveur. |
| `service.appProtocol` | `""` | Valeur du champ `appProtocol` du port du Service. Vide signifie `https` lorsque `tls.enabled` est actif, et aucun champ sinon. |
| `service.annotations` | `{}` | Annotations du Service, par exemple pour un équilibreur de charge interne. |
| `ingress.enabled` | `false` | Génère un Ingress. |
| `ingress.className` | `""` | `ingressClassName` de l'Ingress. |
| `ingress.annotations` | `{}` | Annotations de l'Ingress, par exemple `cert-manager.io/cluster-issuer`. |
| `ingress.hosts` | hôte `github-sts.example.com`, chemin `/` avec `pathType: Prefix` | Règles d'hôtes et de chemins. Remplacez l'hôte d'exemple avant d'activer l'Ingress. |
| `ingress.tls` | `[]` | Blocs TLS. Un Ingress sans bloc TLS expose le point d'entrée d'échange en HTTP clair, ce qui laisse passer le jeton porteur OIDC en clair sur le réseau. |
| `httproute.enabled` | `false` | Génère une HTTPRoute Gateway API. Exige les CRD Gateway API. |
| `httproute.parentRefs` | `[]` | Gateways auxquelles la route se rattache. |
| `httproute.hostnames` | `[]` | Noms d'hôtes que la route reconnaît. |
| `httproute.port` | `8080` | Port du Service de destination vers lequel la route achemine. |
| `httproute.annotations` | `{}` | Annotations de la HTTPRoute. |

## TLS et mTLS

Désactivé par défaut : le pod sert du HTTP en clair et TLS se termine sur l'Ingress ou la Gateway. Voir [TLS et mTLS]({{< relref "tls" >}}) pour savoir quand déplacer la terminaison dans le pod et ce que cela change.

| Valeur | Défaut | Effet |
|---|---|---|
| `tls.enabled` | `false` | Sert HTTPS depuis le pod. Monte `existingSecret`, écrit `server.tls` dans le ConfigMap, renomme le port du conteneur et du Service en `https`, et pointe les sondes, les moniteurs et les hooks de test vers HTTPS. Exige une image serveur qui prend en charge `server.tls`. |
| `tls.existingSecret` | `""` | Secret contenant le certificat de service et sa clé. Obligatoire lorsque `tls.enabled` est vrai : sans lui le rendu échoue. Le chart ne le crée jamais et aucune valeur n'accepte de matériel cryptographique. |
| `tls.certKey` | `"tls.crt"` | Clé de ce Secret contenant la chaîne de certificats au format PEM. |
| `tls.keyKey` | `"tls.key"` | Clé de ce Secret contenant la clé privée au format PEM. |
| `tls.mountPath` | `"/etc/github-sts-tls"` | Emplacement de montage du matériel cryptographique. Gardez-le hors de `/etc/github-sts` : le ConfigMap y est monté en lecture seule, et un runtime de conteneur ne peut pas créer un point de montage à l'intérieur d'un montage en lecture seule. |
| `tls.minVersion` | `"1.2"` | Version TLS minimale acceptée, `"1.2"` ou `"1.3"`. TLS 1.3 supprime la négociation de suites et rejette les clients qui ne le parlent pas, dont l'image BusyBox utilisée par défaut par les hooks de test. |
| `tls.cipherSuites` | `[]` | Liste blanche de suites cryptographiques TLS 1.2, en noms IANA. Vide signifie les valeurs par défaut de Go, déjà limitées aux suites AEAD. La renseigner avec `minVersion: "1.3"` est rejeté : le chart fait alors échouer le rendu. |
| `tls.reloadInterval` | `""` | Intervalle de rechargement du certificat, en durée Go. Vide conserve le certificat lu au démarrage : un renouvellement ne prend effet qu'au redémarrage suivant. |
| `tls.clientAuth.enabled` | `false` | Exige et vérifie un certificat client sur chaque connexion, `/health`, `/ready` et `/metrics` compris. Les sondes basculent en `tcpSocket` et les hooks de test ne sont plus générés, car aucun des deux ne peut présenter de certificat. |
| `tls.clientAuth.existingSecret` | `""` | Secret contenant le bundle de CA clientes de confiance. Vide signifie `tls.existingSecret`, où cert-manager écrit `ca.crt` à côté du certificat de service. |
| `tls.clientAuth.caKey` | `"ca.crt"` | Clé de ce Secret contenant le bundle de CA au format PEM. |

## NetworkPolicy

Les deux familles de politiques sont désactivées par défaut. Activez celle qu'implémente votre CNI, ou les deux.

| Valeur | Défaut | Effet |
|---|---|---|
| `networkPolicy.allowKubeDns` | `true` | Ajoute une règle de sortie DNS sur UDP et TCP 53 aux familles de politiques activées. Sans elle, aucun nom d'hôte ne se résout et tous les échanges échouent. |
| `networkPolicy.native.enabled` | `false` | Génère une NetworkPolicy `networking.k8s.io/v1` avec `policyTypes: [Ingress, Egress]`. Tout ce qui n'est pas listé est refusé. |
| `networkPolicy.native.from` | `[]` | Pairs autorisés à joindre le port du Service. Une liste vide refuse toute entrée interne au cluster, ce qui bloque aussi `helm test`. |
| `networkPolicy.native.cidrs` | `[]` | Plages CIDR autorisées en sortie sur TCP 443. L'API native ne sait pas filtrer par nom d'hôte : les plages GitHub et JWKS doivent être listées et maintenues à la main. |
| `networkPolicy.native.extraIngress` | `[]` | Règles supplémentaires fusionnées dans la politique, au format `NetworkPolicyIngressRule`. |
| `networkPolicy.native.extraEgress` | `[]` | Règles supplémentaires fusionnées dans la politique, au format `NetworkPolicyEgressRule`. |
| `networkPolicy.cilium.enabled` | `false` | Génère une CiliumNetworkPolicy `cilium.io/v2`. Exige la CRD Cilium. |
| `networkPolicy.cilium.fromEndpoints` | `[]` | Sélecteurs d'endpoints autorisés à joindre le port du Service. |
| `networkPolicy.cilium.fqdns` | `[]` | Sélecteurs FQDN autorisés en sortie sur TCP 443, chacun étant une map `matchName` ou `matchPattern`. |
| `networkPolicy.cilium.deriveJwksHostsFromIssuers` | `true` | Ajoute à la liste d'autorisation FQDN l'hôte de chaque entrée de `oidc.allowedIssuers` et chaque hôte listé dans `oidc.trustedJwksHosts`, pour qu'ajouter un émetteur ne casse pas silencieusement la récupération de ses clés. Désactivez pour gérer `fqdns` à la main. |
| `networkPolicy.cilium.extraIngress` | `[]` | Règles d'entrée supplémentaires fusionnées dans la politique. |
| `networkPolicy.cilium.extraEgress` | `[]` | Règles de sortie supplémentaires fusionnées dans la politique. |

## Serveur et journalisation

| Valeur | Défaut | Effet |
|---|---|---|
| `server.shutdownTimeout` | `"10s"` | Budget d'arrêt gracieux, sous forme de durée Go. Doit rester inférieur à `terminationGracePeriodSeconds`. |
| `server.trustForwardedHeaders` | `false` | Lit l'IP du client depuis `X-Forwarded-For`. N'activez que derrière un proxy qui réécrit cet en-tête : sur un serveur joignable directement, un en-tête de confiance permet à l'appelant de forger l'IP sur laquelle s'appuient la limitation de débit et les enregistrements d'audit. |
| `logging.level` | `"info"` | Niveau de journalisation applicatif : debug, info, warn ou error. |
| `logging.suppressHealthLogs` | `true` | Supprime les lignes d'accès pour `/health`, `/ready` et `/metrics`, qui sinon saturent le journal au rythme des sondes. |

## Politique de confiance et OIDC

| Valeur | Défaut | Effet |
|---|---|---|
| `policy.basePath` | `".github/sts"` | Répertoire du dépôt cible contenant les politiques de confiance. Une politique se résout en `{basePath}/{app}/{identity}.sts.yaml`. |
| `policy.cacheTtl` | `"60s"` | Durée de réutilisation d'une politique récupérée. Une valeur élevée réduit les appels à l'API GitHub ; une valeur basse raccourcit la fenêtre pendant laquelle une politique révoquée reste honorée. |
| `oidc.allowedIssuers` | `["https://token.actions.githubusercontent.com"]` | Émetteurs dont les jetons sont acceptés. Un jeton dont l'`iss` n'est pas listé est rejeté avant tout chargement de politique. Gardez cette liste aussi courte que le déploiement le permet. |
| `oidc.requiredAudience` | `""` | Revendication `aud` exigée pour tout le serveur, vérifiée avant le chargement de politique et avant la réservation du JTI. Vide signifie que seul le champ `audience:` de chaque politique s'applique. Renseignez-y l'URL publique de ce déploiement, pour qu'un fichier de politique trop permissif ne puisse pas accepter un jeton émis pour une autre partie de confiance. |
| `oidc.trustedJwksHosts` | `{}` | Liste d'autorisation des hôtes JWKS, par émetteur. Par défaut l'en-tête `Host` de la requête JWKS est épinglé à l'hôte de l'émetteur, pour qu'une réponse DNS forgée ne puisse pas détourner la récupération des clés de signature. Cette map est l'exception pour les émetteurs qui publient leurs clés ailleurs, comme `accounts.google.com` qui les sert depuis `www.googleapis.com`. Les clés sont des URL d'émetteur complètes, les valeurs des listes d'hôtes. |

## Prévention du rejeu

| Valeur | Défaut | Effet |
|---|---|---|
| `jti.backend` | `"memory"` | Où sont consignés les identifiants de jetons consommés : `memory` ou `redis`. `memory` est propre à chaque pod : avec plusieurs réplicas, un jeton rejoué contre un autre pod n'est pas détecté. Utilisez `redis` dès que `replicaCount` dépasse 1 ou que l'autoscaling est actif. |
| `jti.redisUrl` | `""` | URL de connexion Redis. Obligatoire lorsque `backend` vaut `redis`. |
| `jti.ttl` | `"1h"` | Durée de mémorisation d'un identifiant de jeton consommé. Gardez-la au moins égale à la durée de vie maximale acceptée, sinon un jeton redevient rejouable avant d'expirer. |

## Limitation de débit

| Valeur | Défaut | Effet |
|---|---|---|
| `rateLimit.enabled` | `false` | Active la limitation de débit par IP sur `/sts/exchange`. |
| `rateLimit.rate` | `10` | Requêtes par seconde et par IP en régime établi. |
| `rateLimit.burst` | `20` | Tolérance de rafale par IP. |
| `rateLimit.exemptCidrs` | `[]` | Plages CIDR exemptées de la limite. N'exemptez que des plages que vous maîtrisez : la limite s'appuie sur l'IP du client, laquelle n'est fiable que dans la mesure où `server.trustForwardedHeaders` le permet. |

## Audit

| Valeur | Défaut | Effet |
|---|---|---|
| `audit.fileEnabled` | `true` | Écrit le flux d'audit dans un fichier. Le chart monte un `emptyDir` de 100 Mio à cet effet, le système de fichiers racine étant en lecture seule. |
| `audit.filePath` | `"/var/log/github-sts/audit.json"` | Chemin dans le conteneur. C'est son répertoire parent que le chart monte : modifier ce chemin déplace le montage avec lui. |
| `audit.bufferSize` | `1024` | Taille du tampon pour les écritures d'audit asynchrones. |

Un `emptyDir` est supprimé avec le pod. Exportez le flux d'audit hors du nœud avec un collecteur de journaux s'il doit survivre à un redémarrage.

## Métriques

| Valeur | Défaut | Effet |
|---|---|---|
| `metrics.enabled` | `true` | Sert les métriques Prometheus sur `/metrics` et active le test de métriques du chart. |
| `metrics.authToken` | `""` | Jeton porteur exigé sur `/metrics`. Vide laisse le point d'entrée non authentifié, ce qui est acceptable pour un Service `ClusterIP` et ne l'est pas pour un point d'entrée exposé par un Ingress. |
| `metrics.rateLimitPoll.enabled` | `true` | Interroge périodiquement l'API de limite de débit GitHub, pour que le quota restant soit visible avant que les échanges commencent à échouer. |
| `metrics.rateLimitPoll.interval` | `"60s"` | Intervalle d'interrogation de l'API de limite de débit. |
| `metrics.reachabilityProbe.enabled` | `true` | Sonde périodiquement la joignabilité de l'API GitHub, ce qui distingue une panne de sortie réseau d'un refus de politique pendant un incident. |
| `metrics.reachabilityProbe.interval` | `"30s"` | Intervalle de la sonde de joignabilité. |

### ServiceMonitor

Exige les CRD Prometheus Operator. Collecte via le Service.

| Valeur | Défaut | Effet |
|---|---|---|
| `serviceMonitor.enabled` | `false` | Génère un ServiceMonitor. |
| `serviceMonitor.namespace` | `""` | Namespace de l'objet. Vide signifie le namespace de la release. |
| `serviceMonitor.labels` | `{}` | Labels supplémentaires, typiquement celui que sélectionne votre instance Prometheus. |
| `serviceMonitor.annotations` | `{}` | Annotations supplémentaires. |
| `serviceMonitor.interval` | `"30s"` | Intervalle de collecte. |
| `serviceMonitor.scrapeTimeout` | `"10s"` | Délai maximal de collecte. Gardez-le inférieur à l'intervalle. |
| `serviceMonitor.path` | `"/metrics"` | Chemin des métriques. |
| `serviceMonitor.metricRelabelings` | `[]` | Réétiquetage appliqué aux échantillons collectés. |
| `serviceMonitor.relabelings` | `[]` | Réétiquetage appliqué à la cible avant la collecte. |
| `serviceMonitor.honorLabels` | `false` | Donne la priorité aux labels collectés sur ceux de la cible en cas de collision. |
| `serviceMonitor.scheme` | `""` | Schéma de collecte. Vide signifie `https` lorsque `tls.enabled` est actif, et `http` sinon. |
| `serviceMonitor.tlsConfig` | `{}` | Réglages TLS de la collecte. Vide avec `tls.enabled` actif signifie `insecureSkipVerify: true`, car Prometheus se connecte à l'IP du pod, pour laquelle un certificat de service ne porte aucun SAN. Renseignez `ca` et `serverName` pour authentifier la cible, et `cert` avec `keySecret` lorsque `tls.clientAuth.enabled` est actif. |

### PodMonitor

L'alternative au ServiceMonitor : collecte directement auprès des pods, ce qu'il faut lorsque le Service n'est pas le chemin de collecte.

| Valeur | Défaut | Effet |
|---|---|---|
| `podMonitor.enabled` | `false` | Génère un PodMonitor. |
| `podMonitor.namespace` | `""` | Namespace de l'objet. Vide signifie le namespace de la release. |
| `podMonitor.labels` | `{}` | Labels supplémentaires, typiquement celui que sélectionne votre instance Prometheus. |
| `podMonitor.annotations` | `{}` | Annotations supplémentaires. |
| `podMonitor.interval` | `"30s"` | Intervalle de collecte. |
| `podMonitor.scrapeTimeout` | `"10s"` | Délai maximal de collecte. Gardez-le inférieur à l'intervalle. |
| `podMonitor.path` | `"/metrics"` | Chemin des métriques. |
| `podMonitor.metricRelabelings` | `[]` | Réétiquetage appliqué aux échantillons collectés. |
| `podMonitor.relabelings` | `[]` | Réétiquetage appliqué à la cible avant la collecte. |
| `podMonitor.honorLabels` | `false` | Donne la priorité aux labels collectés sur ceux de la cible en cas de collision. |
| `podMonitor.scheme` | `""` | Schéma de collecte. Vide signifie `https` lorsque `tls.enabled` est actif, et `http` sinon. |
| `podMonitor.tlsConfig` | `{}` | Réglages TLS de la collecte. Vide avec `tls.enabled` actif signifie `insecureSkipVerify: true`, car Prometheus se connecte à l'IP du pod, pour laquelle un certificat de service ne porte aucun SAN. Renseignez `ca` et `serverName` pour authentifier la cible, et `cert` avec `keySecret` lorsque `tls.clientAuth.enabled` est actif. |

## Tests Helm

Les pods de hook `helm test`. Voir [Ressources générées]({{< relref "resources" >}}) pour ce que chacun vérifie.

| Valeur | Défaut | Effet |
|---|---|---|
| `tests.enabled` | `true` | Génère les pods de hook de test. Ils sont créés par `helm test`, jamais par `helm install`. Ignorés automatiquement lorsque `tls.clientAuth.enabled` est actif, puisque les hooks ne détiennent aucun certificat client. |
| `tests.image` | `"busybox:1.37"` | Image exécutée par les hooks. Leur script utilise `curl` lorsque l'image le fournit, et se rabat sur `wget`. BusyBox ne parle que TLS 1.2 : `tls.minVersion: "1.3"` exige donc une image curl ici. |

<!-- values:end -->

Activer les deux moniteurs collecte deux fois les mêmes séries. Choisissez-en un.

## Suite

- [Ressources générées]({{< relref "resources" >}}) pour ce que ces valeurs produisent
- [Réseau]({{< relref "networking" >}}) pour les valeurs de routage et de politique en contexte
- [Configuration]({{< relref "/reference/configuration" >}}) pour ce que le serveur fait du fichier de configuration généré
