---
title: Versionnement
description: Comment épingler le chart, comment ses versions sont produites, et où sont publiées les combinaisons de versions prises en charge.
weight: 7
translationKey: helm-chart-versioning
translationStatus: pending-review
---

## Choisir une référence

| Référence | Exemple | À utiliser quand |
|---|---|---|
| Version du chart | `--version 0.0.3` | Choix par défaut. Vous relisez chaque mise à niveau explicitement. |
| Digest du chart | `oci://ghcr.io/depthmark/charts/github-sts@sha256:...` | Vous exigez une référence impossible à déplacer, ou votre moteur de politiques vérifie l'artefact du chart. |
| Aucun drapeau de version | *(omis)* | Jamais. Helm résout le chart publié le plus récent, ce qui fait dépendre la version déployée du moment où la commande a été lancée. |

Ce chart déploie un service qui émet des identifiants. Traitez-le comme toute autre dépendance privilégiée et épinglez-le, dans le fichier de valeurs comme dans l'outil de déploiement continu qui l'applique.

Tant que la version majeure est `0`, un changement incompatible incrémente la version mineure et non la majeure. Lisez le [changelog du chart](https://github.com/Depthmark/github-sts-helm/blob/main/charts/github-sts/CHANGELOG.md) pour toutes les versions traversées, pas seulement celle d'arrivée.

## Version du chart et version applicative

`Chart.yaml` porte deux versions, qui n'ont pas le même sens.

| Champ | Signification |
|---|---|
| `version` | La version du chart lui-même. Elle change dès que les templates ou les valeurs changent, y compris lorsque rien n'a bougé côté serveur. |
| `appVersion` | La version du serveur github-sts contre laquelle le chart a été construit et testé. C'est la valeur par défaut de `image.tag`. |

Elles évoluent aujourd'hui de concert, mais rien ne garantit qu'il en sera toujours ainsi. Épinglez le chart avec `--version`, et épinglez l'image du serveur séparément avec `image.tag` ou `image.digest` lorsque les deux doivent évoluer indépendamment.

## Comment les releases sont produites

Le dépôt utilise [Release Please](https://github.com/googleapis/release-please) avec des [commits conventionnels](https://www.conventionalcommits.org/).

1. Les commits arrivent sur `main` avec un préfixe conventionnel, par exemple `feat:` ou `fix:`.
2. Release Please maintient une pull request de release portant l'incrément de `Chart.yaml` et l'entrée de changelog.
3. Fusionner cette pull request crée la release GitHub et le tag, préfixé par le composant : `github-sts-v0.0.3`.
4. Le workflow de release empaquette le chart, le publie sur `ghcr.io/depthmark/charts/github-sts`, le signe avec cosign et y attache une attestation de provenance de build.
5. Le workflow refuse de publier si la version du tag et celle de `Chart.yaml` divergent.

Le workflow de release s'authentifie auprès de GitHub avec [github-sts-action]({{< relref "/integrations/github-action" >}}) plutôt qu'avec un identifiant stocké : le dépôt ne conserve donc aucun jeton d'accès personnel pour ses propres releases.

## Quelle version de serveur utiliser

Les combinaisons vérifiées de versions du serveur, du chart et de l'action sont publiées dans [Compatibilité]({{< relref "/integrations/compatibility" >}}). Consultez cette page avant de mettre à niveau un composant isolément, en particulier avant d'éloigner `image.tag` de l'`appVersion` du chart.

## Comment cette documentation est publiée

Les pages de cette section vivent dans le dépôt du chart, sous `docs/content/`, et sont intégrées à ce site comme [module Hugo](https://gohugo.io/hugo-modules/) épinglé à une version précise. La compilation du site résout cette version via le proxy de modules Go : une compilation de la documentation est donc reproductible et ne récupère jamais de contenu non relu depuis une branche par défaut.

Le module est déclaré à la racine du dépôt plutôt que dans `docs/` : il porte donc la version du dépôt lui-même et n'exige aucun tag de documentation distinct. Les tags de release du chart sont préfixés par le composant — `github-sts-v0.0.3` — ce que le proxy de modules Go ne reconnaît pas comme une version de module. Le site épingle donc le SHA du commit de la release, que le proxy résout en pseudo-version, tout aussi immuable qu'un tag.

Publier un changement de documentation demande donc deux fusions : une dans le dépôt du chart, et une dans le dépôt du site qui fait avancer l'épinglage. Cette seconde fusion est le point de contrôle.
