---
title: Chart Helm
description: Déployez github-sts sur Kubernetes avec le chart Helm officiel, à partir d'un paquet OCI signé.
weight: 1
translationKey: helm-chart
translationStatus: pending-review
aliases:
  - /fr/integrations/deploy-with-helm/
---

[github-sts-helm](https://github.com/Depthmark/github-sts-helm) empaquette le serveur github-sts pour Kubernetes. Le chart génère un Deployment, un Service et un ConfigMap contenant la configuration du serveur, puis monte la clé privée de chaque GitHub App depuis un Secret que vous créez vous-même. Le chart ne conserve jamais de clé privée dans ses valeurs.

Le chart est publié sous forme d'artefact OCI signé sur `ghcr.io/depthmark/charts/github-sts` et fournit une attestation de provenance de build.

{{< cards >}}
{{< card link="quickstart" title="Démarrage rapide" icon="play" subtitle="Un déploiement mono-app fonctionnel, à partir d'un namespace vide" >}}
{{< card link="installation" title="Installation" icon="download" subtitle="Installation OCI, plusieurs apps, registres privés, épinglage par digest" >}}
{{< card link="values" title="Référence des valeurs" icon="adjustments" subtitle="Chaque valeur du chart, avec sa valeur par défaut et son effet" >}}
{{< card link="resources" title="Ressources générées" icon="cube" subtitle="Ce que produit chaque template et ce qui le conditionne" >}}
{{< card link="networking" title="Réseau" icon="globe-alt" subtitle="Ingress, HTTPRoute et NetworkPolicy pour les deux familles de CNI" >}}
{{< card link="upgrade" title="Mise à niveau" icon="arrow-circle-up" subtitle="Déployer une nouvelle version de chart ou d'image, et revenir en arrière" >}}
{{< card link="versioning" title="Versionnement" icon="tag" subtitle="Épinglage du chart, processus de release et combinaisons prises en charge" >}}
{{< /cards >}}

## Limites de cette documentation

Cette section documente le chart : ses valeurs, les objets Kubernetes qu'il génère, son chemin de mise à niveau et son versionnement.

Le comportement du serveur est documenté ailleurs sur ce site. Ce que le serveur fait de la configuration écrite par ce chart est décrit dans [Configuration]({{< relref "/reference/configuration" >}}), les champs des politiques de confiance et leur évaluation dans [Politiques de confiance]({{< relref "/concepts/trust-policies" >}}), et le point d'entrée d'échange dans la [Référence de l'API]({{< relref "/reference/api" >}}). Le côté client de l'échange est documenté dans [GitHub Action]({{< relref "/integrations/github-action" >}}).
