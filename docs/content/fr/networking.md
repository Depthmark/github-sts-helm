---
title: Réseau
description: Exposez le point d'entrée d'échange avec Ingress ou HTTPRoute, et restreignez ce que les pods peuvent joindre avec l'une ou l'autre famille de NetworkPolicy.
weight: 5
translationKey: helm-chart-networking
translationStatus: pending-review
---

Une installation par défaut génère un Service `ClusterIP` et rien d'autre. Les clients extérieurs au cluster n'atteignent le point d'entrée d'échange qu'une fois une route activée, et les pods peuvent joindre n'importe quelle destination tant qu'aucune politique n'est activée.

## Exposer le point d'entrée

Activez exactement l'un de `ingress` et `httproute`. Les deux acheminent vers le même Service, et activer les deux laisse deux chemins indépendants vers le même point d'entrée, avec deux configurations TLS indépendantes.

Les deux terminent TLS devant le pod, ce qui laisse du HTTP en clair sur le saut entre le proxy et le Service. [TLS et mTLS]({{< relref "tls" >}}) couvre les déploiements où ce saut doit lui aussi être chiffré, et ceux où les clients doivent présenter un certificat.

### Ingress

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: sts.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: github-sts-tls
      hosts:
        - sts.example.com
```

La valeur par défaut de `hosts` contient l'hôte d'exemple `github-sts.example.com`. Remplacez-le : activer `ingress` sans modifier `hosts` publie une route pour un nom d'hôte qui ne vous appartient pas.

Configurez TLS. Les clients envoient le jeton OIDC comme identifiant porteur dans l'en-tête `Authorization` : un Ingress sans bloc `tls` fait donc circuler en clair une assertion d'identité signée, susceptible d'être capturée et rejouée jusqu'à son expiration.

### HTTPRoute

L'alternative Gateway API. Exige les CRD Gateway API et une Gateway existante ; TLS se termine sur l'écouteur de la Gateway et non dans ce chart.

```yaml
httproute:
  enabled: true
  parentRefs:
    - name: external
      namespace: gateway-system
      sectionName: https
  hostnames:
    - sts.example.com
  port: 8080
```

La route générée reconnaît le préfixe de chemin `/` et achemine vers le Service sur `httproute.port`. Les entrées de `parentRefs` acceptent `name`, et facultativement `kind`, `group`, `namespace` et `sectionName`.

## Restreindre le trafic

Le chart fournit deux templates de NetworkPolicy et n'en active aucun. Choisissez celui qu'implémente votre CNI ; activer les deux est une défense en profondeur raisonnable sur un cluster Cilium qui honore aussi l'API standard.

Les deux ne concernent que les pods de ce chart, et suivent la même structure :

- **Entrée :** qui peut joindre le port du Service. Laissez la liste de pairs vide et aucun trafic interne au cluster n'est admis.
- **Sortie :** DNS, plus TCP 443 vers les destinations que vous autorisez.

Le serveur a besoin de joindre deux types de destination : l'API GitHub, et le point d'entrée JWKS de chaque émetteur listé dans `oidc.allowedIssuers`. En oublier un fait échouer les échanges sur une erreur de connexion plutôt que sur un refus de politique, ce qui est bien plus difficile à interpréter pendant un incident.

### NetworkPolicy native

Fonctionne sur tout CNI implémentant `networking.k8s.io/v1`. Cette API ne sait pas filtrer une destination par nom d'hôte : les destinations externes sont donc des plages CIDR que vous maintenez.

```yaml
networkPolicy:
  allowKubeDns: true
  native:
    enabled: true
    from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: ingress-nginx
    cidrs:
      - 140.82.112.0/20
      - 192.30.252.0/22
```

La politique générée pose `policyTypes: [Ingress, Egress]` : tout ce qui n'est pas listé est refusé. `cidrs` n'ouvre que TCP 443.

GitHub publie ses plages sur [`https://api.github.com/meta`](https://api.github.com/meta), et elles évoluent. Intégrez leur relecture à votre routine de mise à niveau, car une plage disparue de votre liste d'autorisation se manifeste par des échecs d'échange intermittents.

### CiliumNetworkPolicy

Exige la CRD Cilium, et filtre la sortie par nom d'hôte, ce qui supprime la maintenance des CIDR.

```yaml
networkPolicy:
  allowKubeDns: true
  cilium:
    enabled: true
    fromEndpoints:
      - matchLabels:
          io.kubernetes.pod.namespace: ingress-nginx
    fqdns:
      - matchName: api.github.com
```

`deriveJwksHostsFromIssuers` est actif par défaut. Le chart ajoute à la liste d'autorisation FQDN, sous forme d'entrées `matchName`, l'hôte de chaque entrée de `oidc.allowedIssuers` ainsi que chaque hôte listé dans `oidc.trustedJwksHosts`. Ajouter un émetteur ouvre donc automatiquement la récupération de ses clés, et un émetteur qui sert ses JWKS depuis un autre hôte — `accounts.google.com` signant des jetons dont les clés vivent sur `www.googleapis.com` — est couvert dès que vous le déclarez dans `oidc.trustedJwksHosts`.

Ne mettez `deriveJwksHostsFromIssuers: false` que si vous comptez maintenir `fqdns` à la main : les entrées dérivées disparaissent avec ce réglage.

### DNS

`networkPolicy.allowKubeDns` vaut `true` par défaut et s'applique aux familles de politiques activées. Il autorise UDP et TCP 53 vers `kube-dns` dans `kube-system`. Le désactiver sans fournir votre propre règle DNS dans `extraEgress` casse toute résolution de nom, y compris les règles FQDN ci-dessus, qui résolvent les noms avant de pouvoir les reconnaître.

### Le reste

`extraIngress` et `extraEgress` sont fusionnés tels quels dans la politique générée, au format de l'API que vous avez activée. Utilisez-les pour un backend Redis, un proxy de sortie ou un collecteur de métriques non couvert par les listes de pairs.

```yaml
networkPolicy:
  native:
    extraEgress:
      - to:
          - podSelector:
              matchLabels:
                app.kubernetes.io/name: redis
        ports:
          - port: 6379
            protocol: TCP
```

## Vérifier

Effectuez le rendu de la politique et relisez-la avant de l'appliquer :

```bash
helm template github-sts charts/github-sts --values values.yaml \
  --show-only templates/networkpolicy.yaml
```

Confirmez ensuite depuis un pod que les destinations attendues sont bien celles qui fonctionnent :

```bash
kubectl exec --namespace github-sts deploy/github-sts -- \
  wget -qO- https://api.github.com/meta > /dev/null && echo reachable
```

Une politique qui refuse l'entrée interne au cluster refuse aussi les Pods de test du chart, et `helm test` se met à échouer. Ajoutez leur namespace à la liste de pairs pour continuer à l'utiliser.

## Suite

- [Référence des valeurs]({{< relref "values" >}}) pour toutes les valeurs de routage et de politique
- [Ressources générées]({{< relref "resources" >}}) pour les objets produits par ces valeurs
- [Dépannage]({{< relref "/operations/troubleshooting" >}}) pour interpréter un échange en échec
