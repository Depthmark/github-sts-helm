---
title: Mise à niveau
description: Déployez une nouvelle version de chart ou d'image, comprenez ce qui déclenche un redémarrage de pod, et revenez en arrière si nécessaire.
weight: 7
translationKey: helm-chart-upgrade
translationStatus: pending-review
---

## Mettre à niveau le chart

```bash
helm upgrade github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --namespace github-sts \
  --version 0.0.3 \
  --values values.yaml
```

Deux habitudes rendent l'opération sûre.

Passez `--values` à chaque mise à niveau. Helm ne reprend pas les valeurs de la release précédente sans `--reuse-values`, et mélanger les deux approches d'une mise à niveau à l'autre est la façon la plus courante de voir un réglage revenir silencieusement à sa valeur par défaut. Gardez le fichier de valeurs sous gestion de version et traitez-le comme la source de vérité.

Passez `--version` à chaque mise à niveau. Sans ce drapeau, Helm résout ce qui est le plus récent dans le registre à cet instant, ce qui fait dépendre la version déployée du moment où la commande a été lancée.

Relisez le changement avant de l'appliquer :

```bash
helm diff upgrade github-sts oci://ghcr.io/depthmark/charts/github-sts \
  --namespace github-sts --version 0.0.3 --values values.yaml
```

`helm diff` est le greffon [helm-diff](https://github.com/databus23/helm-diff). À défaut, `helm template ... | kubectl diff -f -` en fait l'essentiel.

## Les routes ne publient plus que `/sts/`

Les versions précédentes du chart donnaient à `ingress.hosts[].paths` la valeur par défaut `/` avec `pathType: Prefix`, et généraient la HTTPRoute avec une correspondance `PathPrefix` figée sur `/`. Dans les deux cas, `/health`, `/ready` et `/metrics` étaient publiés sur le nom d'hôte public à côté du point d'entrée d'échange. Les deux valent désormais `/sts/` par défaut.

La mise à niveau restreint la route, sauf si votre fichier de valeurs définit lui-même le chemin. Deux points à vérifier avant de la déployer :

- Tout ce qui, hors du cluster, appelle `/health`, `/ready` ou `/metrics` via la route — une sonde de disponibilité externe, un Prometheus qui scrute à travers le répartiteur de charge — cesse de répondre. Déplacez-le dans le cluster, ou rajoutez le chemin explicitement.
- Un fichier de valeurs qui fixe `path: /` conserve la route large. La restreindre est une modification de valeurs, et [Réseau]({{< relref "networking" >}}) décrit ce que la route large expose.

`httproute.paths` est nouveau, et ne peut pas être vide : Gateway API interprète une règle sans correspondance comme correspondant à tous les chemins, le chart refuse donc de se générer plutôt que de tout publier.

## Ce qui déclenche un redémarrage

Le template de pod porte `checksum/config`, une empreinte du ConfigMap généré. Tout changement d'une valeur côté serveur — un émetteur, une audience, un niveau de journalisation, un TTL de politique — modifie cette empreinte et fait rouler les pods. C'est délibéré : le serveur lit sa configuration au démarrage, donc une mise à jour du ConfigMap qui ne ferait pas rouler les pods laisserait le processus sur l'ancienne configuration sans aucun signal de cette divergence.

En pratique, ce chart roule plus souvent qu'un chart classique. C'est aussi la raison pour laquelle `revisionHistoryLimit` vaut `5` par défaut.

Une mise à jour progressive draine pendant `terminationGracePeriodSeconds`, soit 30 secondes par défaut, et pendant le `server.shutdownTimeout` du serveur, soit 10 secondes par défaut. Les échanges en cours se terminent tant que la période de grâce reste confortablement supérieure au délai d'arrêt.

## Mettre à niveau l'image du serveur

`image.tag` suit l'`appVersion` du chart : une mise à niveau du chart embarque donc normalement l'image serveur correspondante. Ne surchargez l'image que pour faire évoluer les deux indépendamment :

```yaml
image:
  tag: "0.0.3"
```

Sur un cluster qui vérifie les images à l'admission, épinglez plutôt `image.digest` et laissez `tag` vide. Voir [Installation]({{< relref "installation" >}}).

Consultez [Compatibilité]({{< relref "/integrations/compatibility" >}}) avant d'éloigner l'image serveur de l'`appVersion` du chart. Cette page liste les combinaisons vérifiées de versions du serveur, du chart et de l'action.

## Changer la clé privée

Le chart monte la clé depuis un Secret qu'il ne possède pas : la rotation d'une clé est donc une opération en deux temps.

```bash
kubectl create secret generic github-sts-default-app \
  --namespace github-sts \
  --from-file=github-app-private-key=./new-key.pem \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/github-sts --namespace github-sts
```

Mettre à jour le Secret ne redémarre rien, et le serveur conserve la clé lue au démarrage. C'est le redémarrage qui met la nouvelle clé en service. Générez la nouvelle clé dans GitHub et laissez les deux clés valides avant de supprimer l'ancienne, pour qu'un pod pas encore roulé continue de fonctionner.

## Convertir une app en pool

Faire passer une entrée d'une seule GitHub App à `instances` remplace `appId` et `existingSecret` par une liste : c'est une modification d'entrée, pas un ajout.

```yaml
github:
  apps:
    checkout:
      instances:
        - name: checkout-1
          appId: "111111"          # l'App déjà utilisée par cette entrée
          existingSecret: github-sts-checkout-1
        - name: checkout-2
          appId: "222222"          # nouvellement enregistrée et installée
          existingSecret: github-sts-checkout-2
```

Trois points à connaître avant de l'appliquer.

L'image serveur doit gérer les pools. Une image plus ancienne ignore `instances:` et se retrouve alors sans identifiants pour cette app, ce qui fait échouer tous ses échanges. Déplacez `image.tag` ou `image.digest` d'abord, vérifiez, puis changez les valeurs.

Enregistrer une deuxième GitHub App ne suffit pas : installez-la sur les mêmes dépôts, avec les mêmes permissions, que celle déjà en service. Le serveur considère les membres d'un pool comme interchangeables et ne vérifie pas qu'ils le sont.

Les métriques gagnent une étiquette `instance`. Toutes les séries GitHub App, de limitation de débit et d'accessibilité deviennent par instance, y compris pour les apps laissées à une seule App, qui compte comme un pool d'une instance. Les tableaux de bord et alertes qui agrègent ces séries ont besoin d'un `sum by (app)` ou équivalent avant la mise à niveau, sans quoi ils afficheront une série par instance. `githubsts_app_pool_exhausted_total` est le signal à alerter : il s'incrémente lorsque toutes les instances d'un pool ont échoué pour une même requête.

Gardez l'ancienne App installée tant que le pool n'a pas servi de trafic. Le retour arrière est un `helm rollback`, qui restaure l'entrée précédente et son montage, mais ne fonctionne que si l'App qu'elle nomme est encore installée.

## Revenir en arrière

```bash
helm history github-sts --namespace github-sts
helm rollback github-sts 3 --namespace github-sts
```

`revisionHistoryLimit` borne la profondeur atteignable par `kubectl rollout undo` au niveau des ReplicaSets. L'historique propre à Helm est distinct et borné par `--history-max` côté client : les deux ne s'accordent donc pas nécessairement sur la profondeur disponible.

Un retour arrière restaure le ConfigMap en même temps que le Deployment : il annule donc aussi bien un changement de configuration serveur qu'un changement d'image.

## Avant une mise à niveau en production

1. Lisez le [changelog du chart](https://github.com/Depthmark/github-sts-helm/blob/main/charts/github-sts/CHANGELOG.md) pour toutes les versions traversées.
2. Vérifiez [Compatibilité]({{< relref "/integrations/compatibility" >}}) pour les versions de serveur et d'action que vous exploitez.
3. Comparez le rendu avec l'état du cluster.
4. Confirmez que `pdb.enabled` est vrai et que `replicaCount` dépasse 1, pour que le déploiement progressif ne puisse pas interrompre le service.
5. Mettez à niveau, puis lancez `helm test`.

## Suite

- [Versionnement]({{< relref "versioning" >}}) pour la façon dont les versions du chart sont produites
- [Référence des valeurs]({{< relref "values" >}}) pour les valeurs qu'une mise à niveau peut modifier
- [Mises à niveau]({{< relref "/operations/upgrades" >}}) pour les recommandations propres au serveur
