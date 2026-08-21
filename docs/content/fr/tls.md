---
title: TLS et mTLS
description: Servir HTTPS depuis le pod plutôt que de terminer en périphérie, renouveler le certificat sans redémarrage, et exiger des certificats clients.
weight: 6
translationKey: helm-chart-tls
translationStatus: pending-review
---

Par défaut, le pod sert du HTTP en clair et quelque chose devant lui termine TLS : le contrôleur d'Ingress via `ingress.tls`, ou le listener de la Gateway auquel une HTTPRoute se rattache. Ce modèle est le plus simple et convient à la plupart des déploiements. Voir [Réseau]({{< relref "networking" >}}) pour les deux routes.

Le bloc `tls` couvre les déploiements où cela ne suffit pas :

- le saut entre le proxy et le pod doit lui aussi être chiffré, parce qu'un maillage rechiffre le trafic vers les backends, parce qu'une `BackendTLSPolicy` Gateway API l'exige, ou parce qu'un contrôle de sécurité impose le chiffrement en transit partout
- rien ne se trouve devant le Service : le pod est alors le point de terminaison TLS
- les clients doivent prouver leur identité avec un certificat, et pas seulement avec un jeton OIDC

## Prérequis

Une image serveur qui prend en charge la section de configuration `server.tls`. Un serveur qui ignore cette section continue de servir du HTTP en clair alors que le chart a déjà pointé les sondes vers HTTPS : les pods échouent à la disponibilité et la release ne termine jamais son déploiement.

La prise en charge est arrivée après la version serveur `v0.0.3` et, à l'heure où ces lignes sont écrites, aucune version publiée ne l'embarque. `image.tag` vaut par défaut l'`appVersion` du chart : une installation par défaut tire donc une image sans `server.tls`. Renseignez `image.tag` avec une version qui en dispose. La page [Compatibilité]({{< relref "/integrations/compatibility" >}}) liste les combinaisons vérifiées.

Une image assez récente pour `server.tls` l'est aussi pour exiger une valeur `bundle_enforcement` de premier niveau, que le chart ne génère pas. Fournissez-la via `extraEnv` comme décrit sous [Bundles de politiques]({{< relref "values#bundles-de-politiques" >}}), sinon le pod ne démarre pas, avant même que TLS entre en jeu.

Un certificat et une clé dans un Secret dont vous êtes propriétaire. Le chart ne génère jamais de certificat. Un Secret `kubernetes.io/tls` produit par cert-manager, par une PKI interne ou par `kubectl create secret tls` convient tel quel, puisque `tls.certKey` et `tls.keyKey` valent déjà `tls.crt` et `tls.key`. Un certificat auto-signé est un outil de test local : il force chaque client à faire confiance à une CA créée pour une seule charge de travail, soit l'inverse de ce à quoi sert un certificat. La page [Tests TLS en local]({{< relref "/operations/tls-local-testing" >}}) couvre ce cas.

## Servir HTTPS depuis le pod

```yaml
tls:
  enabled: true
  existingSecret: github-sts-tls
  reloadInterval: "1h"
```

Le chart refuse de rendre `tls.enabled: true` sans `tls.existingSecret`, plutôt que de démarrer un pod qui n'a aucun certificat à servir.

Activer TLS change cinq choses, et délibérément pas une sixième :

| Quoi | Changement |
|---|---|
| Matériel cryptographique | Projeté en lecture seule sur `tls.mountPath`, `/etc/github-sts-tls` par défaut, et écrit dans le ConfigMap sous `server.tls.cert_file` et `server.tls.key_file`. |
| Port du conteneur et du Service | Nommé `https` au lieu de `http`, et le port du Service reçoit `appProtocol: https`. Les maillages de services et certains contrôleurs d'Ingress lisent le nom du port pour décider comment parler au backend. |
| Sondes | `httpGet` avec `scheme: HTTPS`. Le kubelet ne vérifie pas le certificat lors d'une sonde : un certificat valide uniquement pour le nom d'hôte public passe donc quand même. |
| Collecte Prometheus | Les endpoints ServiceMonitor et PodMonitor reçoivent `scheme: https`. |
| Hooks `helm test` | Interrogent l'endpoint en HTTPS sans vérifier le certificat. |
| Le proxy en amont | Rien. L'Ingress et la Gateway continuent d'envoyer du HTTP en clair tant que vous ne les configurez pas, ce qui est l'objet de la section suivante. |

Le chemin par défaut est un répertoire distinct plutôt qu'un sous-répertoire de `/etc/github-sts`, ce qui garde le matériel cryptographique séparé du montage de configuration et des montages de clés par app. Remplacez `tls.mountPath` par n'importe quel chemin que le conteneur n'utilise pas déjà.

### Renouveler sans redémarrage

`tls.reloadInterval` est une durée Go. Le serveur interroge les fichiers montés à cet intervalle et recharge la paire de clés en place dès que l'un des deux change. Laissez la valeur vide et le processus conserve le certificat lu au démarrage : un renouvellement ne prend alors effet qu'au redémarrage suivant du pod.

Kubernetes met à jour un Secret monté en place, donc rien d'autre n'est nécessaire pour que le nouveau fichier apparaisse dans le pod. Choisissez un intervalle nettement inférieur à la fenêtre de renouvellement. cert-manager renouvelle par défaut aux deux tiers de la durée de vie du certificat : une interrogation horaire est confortable pour un certificat de 90 jours et reste assez réactive pour un certificat de courte durée.

## Indiquer au proxy de parler HTTPS

Activer `tls` ne reconfigure pas ce qui se trouve devant le Service, et le protocole du backend dépend du contrôleur.

Pour ingress-nginx :

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
```

Pour Gateway API, ajoutez une `BackendTLSPolicy` à côté de la release. Le chart n'en génère pas, car la version de l'API suit l'installation de Gateway API de votre cluster plutôt que le chart :

```yaml
apiVersion: gateway.networking.k8s.io/v1alpha3
kind: BackendTLSPolicy
metadata:
  name: github-sts
spec:
  targetRefs:
    - group: ""
      kind: Service
      name: github-sts
      sectionName: https
  validation:
    caCertificateRefs:
      - group: ""
        kind: Secret
        name: github-sts-tls
    hostname: sts.example.com
```

Un proxy qui envoie encore du HTTP en clair à un listener HTTPS renvoie une erreur de passerelle à chaque client, et les pods restent sains pendant ce temps : la panne ressemble alors à un problème de routage plutôt qu'à un problème de TLS.

## Exiger des certificats clients

```yaml
tls:
  enabled: true
  existingSecret: github-sts-tls
  clientAuth:
    enabled: true
    existingSecret: github-sts-client-ca
    caKey: ca.crt
```

Laissez `clientAuth.existingSecret` vide et le bundle de CA est lu depuis `tls.existingSecret`, où cert-manager écrit `ca.crt` à côté du certificat de service.

Le serveur exige et vérifie un certificat client pour tout le listener. `/health`, `/ready` et `/metrics` ne font pas exception : tout appelant incapable de présenter un certificat perd l'accès dès la poignée de main. Le chart ajuste ce qu'il contrôle :

| Appelant | Ce que fait le chart |
|---|---|
| Sondes du kubelet | Bascule les sondes de démarrage, de disponibilité et de vivacité en `tcpSocket`. Le kubelet ne peut pas présenter de certificat client, et une sonde HTTPS contre ce listener échouerait à la poignée de main et redémarrerait le conteneur en boucle. |
| Hooks `helm test` | Ne sont plus générés. Les Pods de hook n'ont aucun certificat, donc chaque vérification échouerait à la poignée de main. |
| Prometheus | Rien d'automatique. Placez les identifiants clients dans `serviceMonitor.tlsConfig` ou `podMonitor.tlsConfig`, sinon la collecte échoue. |

Le changement de sondes représente une vraie perte de signal. Une sonde `tcpSocket` prouve que le listener accepte les connexions, pas que `/ready` retourne 200 : un serveur démarré mais pas prêt reste donc dans les endpoints du Service. Un contrôle de disponibilité plus riche doit venir d'un appelant qui détient un certificat. `probes.mode: httpGet` rétablit les sondes HTTPS, qui échouent alors à la poignée de main comme tout autre client sans certificat. Ce réglage n'est correct que si quelque chose d'autre termine le mTLS devant le conteneur.

## Collecter les métriques en TLS

Avec `tls.enabled` et aucune configuration explicite, le chart écrit `insecureSkipVerify: true` dans l'endpoint de collecte. Prometheus se connecte à l'IP du pod, et un certificat émis pour le Service ou pour le nom d'hôte public ne porte aucun SAN correspondant : la vérification échouerait à chaque collecte. La collecte est chiffrée, la cible n'est pas authentifiée.

Authentifiez correctement la cible en nommant la CA et le nom d'hôte pour lequel le certificat a été émis :

```yaml
serviceMonitor:
  enabled: true
  tlsConfig:
    ca:
      secret:
        name: github-sts-tls
        key: ca.crt
    serverName: sts.example.com
```

Sous `clientAuth`, ajoutez les identifiants clients que Prometheus doit présenter :

```yaml
serviceMonitor:
  tlsConfig:
    cert:
      secret:
        name: prometheus-client-cert
        key: tls.crt
    keySecret:
      name: prometheus-client-cert
      key: tls.key
```

`podMonitor.tlsConfig` prend la même forme. Renseigner l'un ou l'autre remplace la valeur par défaut : `insecureSkipVerify` disparaît dès que vous fournissez votre propre bloc.

## Choisir une version et des suites cryptographiques

`tls.minVersion` accepte `"1.2"`, la valeur par défaut, et `"1.3"`. Sous TLS 1.3, les suites cryptographiques ne sont plus configurables, et les clients qui ne parlent pas 1.3 sont rejetés, dont l'image BusyBox exécutée par défaut par les hooks `helm test`.

`tls.cipherSuites` est une liste d'autorisation de noms IANA, valable uniquement pour TLS 1.2. Laissez-la vide et le serveur utilise les valeurs par défaut de Go : échange de clés ECDHE partout, AES-GCM et ChaCha20-Poly1305 préférés, mais AES-CBC avec un MAC SHA-1 encore accepté si un client l'exige. Renseignez la liste lorsque ce dernier point ne vous convient pas. La renseigner avec `minVersion: "1.3"` est une erreur de configuration que le serveur rejette au démarrage : le chart fait donc échouer le rendu.

```yaml
tls:
  minVersion: "1.2"
  cipherSuites:
    - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
    - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
```

## Vérifier

Lisez ce que le chart a écrit avant d'appliquer :

```bash
helm template github-sts charts/github-sts --values values.yaml \
  --show-only templates/configmap.yaml
```

Vérifiez que les sondes correspondent au listener :

```bash
kubectl get deployment github-sts --namespace github-sts \
  -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}'
```

`httpGet` avec `"scheme":"HTTPS"` correspond au cas TLS, `tcpSocket` au cas mTLS, et un `httpGet` simple signifie que `tls.enabled` n'a jamais pris effet.

Vérifiez que l'endpoint répond en TLS depuis l'intérieur du cluster :

```bash
kubectl run tls-check --rm -i --restart=Never --namespace github-sts \
  --image=curlimages/curl:8.11.1 -- -sS -k https://github-sts:8080/health
```

`-k` ignore la vérification : cela prouve que TLS est servi, pas que le certificat est celui que vous vouliez servir. Pour contrôler le certificat lui-même, redirigez le port et lisez la chaîne :

```bash
kubectl port-forward --namespace github-sts svc/github-sts 8443:8080
openssl s_client -connect localhost:8443 -showcerts </dev/null
```

Sous `clientAuth`, la même commande échoue à la poignée de main tant qu'elle ne présente pas de certificat :

```bash
openssl s_client -connect localhost:8443 -cert client.crt -key client.key </dev/null
```

Terminez avec les hooks du chart, qui suivent le schéma automatiquement :

```bash
helm test github-sts --namespace github-sts
```

## Limites connues

- Sous `clientAuth`, les sondes prouvent seulement que le port accepte les connexions, et `helm test` n'est plus disponible.
- Les hooks `helm test` exécutent BusyBox, dont `wget` ne parle que TLS 1.2. Avec `minVersion: "1.3"`, pointez `tests.image` vers une image curl telle que `curlimages/curl:8.11.1`. Le script des hooks préfère `curl` lorsque l'image le fournit et se rabat sur `wget`.
- `tls.mountPath` ne peut pas être un sous-répertoire de `/etc/github-sts`.
- Le chart monte les certificats et ne les crée jamais. Le renouvellement appartient à cert-manager ou à votre PKI.
- Prometheus n'authentifie pas la cible tant que vous ne configurez pas `tlsConfig` vous-même.

## Suite

- [Référence des valeurs]({{< relref "values" >}}) pour chaque valeur `tls` et son défaut
- [Ressources générées]({{< relref "resources" >}}) pour les montages et les ports que ces valeurs modifient
- [Réseau]({{< relref "networking" >}}) pour la route placée devant le Service
- [Configuration]({{< relref "/reference/configuration" >}}) pour ce que le serveur fait du bloc `server.tls` écrit par ce chart
- [Modèle de sécurité]({{< relref "/concepts/security-model" >}}) pour ce que le serveur authentifie par-dessus le transport
