# BPEL Supply Chain Choreography

## 1. Objectifs pédagogiques
- Comprendre la différence entre orchestration centralisée et chorégraphie décentralisée.
- Concevoir trois processus BPEL asynchrones échangeant via des Partner Links.
- Utiliser les activités clés `<receive>`, `<invoke>`, `<assign>`, `<wait>`, `<flow>`/`<pick>`.
- Manipuler des WSDL décrivant des interactions request/callback.
- Déployer l'ensemble sur Apache ODE/Tomcat via Docker et tester avec SoapUI.

## 2. Participants et rôles
1. **StoreProcess** (initiateur) : démarre le réapprovisionnement, invoque le fabricant, attend deux callbacks.
2. **ManufacturerProcess** : reçoit la commande, simule la fabrication, invoque le transporteur, notifie le magasin.
3. **ShipperProcess** : reçoit la demande d'expédition, simule la préparation, notifie le magasin.

Aucun orchestrateur global : chaque processus agit de sa propre initiative selon les contrats WSDL partagés.

## 3. Architecture de dossiers
```
BPEL_PROJECT/
├─ wsdl/
│   ├─ Manufacturer.wsdl
│   ├─ Shipper.wsdl
│   └─ Store.wsdl
│
├─ schemas/            # XSD communs pour orderDetails, statusInfo, etc.
│
├─ processes/
│   ├─ ManufacturerProcess/
│   │   ├─ ManufacturerProcess.bpel
│   │   └─ deploy.xml
│   ├─ ShipperProcess/
│   │   ├─ ShipperProcess.bpel
│   │   └─ deploy.xml
│   └─ StoreProcess/
│       ├─ StoreProcess.bpel
│       └─ deploy.xml
│
├─ tests/
│   └─ StoreProcess-soapui-project.xml
│
├─ docker/
│   ├─ Dockerfile.ode
│   ├─ Dockerfile.soapui-cli
│   └─ docker-compose.yml
│
└─ README.md
```

## 4. Contrats WSDL
Chaque service expose un portType "service" et un portType "callback" pour supporter les invocations asynchrones. Ajouter les `partnerLinkType` (namespace `http://docs.oasis-open.org/wsbpel/2.0/process/executable`) pour permettre la configuration des Partner Links côté BPEL.

### 4.1 Manufacturer.wsdl
- `requestOrder(orderDetails)` : message d'entrée du magasin.
- `sendManufacturingStatus(statusInfo)` : callback vers le magasin (statut TERMINE, id commande).

### 4.2 Shipper.wsdl
- `requestShipping(shippingDetails)` : message du fabricant (id commande, adresse livraison).
- `sendShippingStatus(statusInfo)` : callback vers le magasin (statut EXPEDIE, trackingId).

### 4.3 Store.wsdl
- `startRestock(productInfo)` : opération client pour démarrer le processus Store.
- `receiveManufacturingStatus(statusInfo)` : notification du fabricant.
- `receiveShippingStatus(statusInfo)` : notification du transporteur.

## 5. Processus BPEL

### 5.1 ManufacturerProcess
- `<receive createInstance="yes">` sur `requestOrder` (Store).
- `<wait for="'PT30S'"/>` pour simuler la fabrication.
- `<assign>` : mappe `orderDetails` vers `shippingDetails` (ajout adresse).
- `<invoke>` asynchrone vers Shipper (`requestShipping`).
- `<assign>` : prépare `statusInfo` (statut TERMINE).
- `<invoke>` callback vers Store (`sendManufacturingStatus`).

### 5.2 ShipperProcess
- `<receive createInstance="yes">` sur `requestShipping` (Manufacturer).
- `<wait for="'PT15S'"/>` pour simuler la préparation.
- `<assign>` : génère trackingId + statut EXPEDIE.
- `<invoke>` callback vers Store (`sendShippingStatus`).

### 5.3 StoreProcess
- `<receive createInstance="yes">` sur `startRestock` (client).
- `<assign>` : compose l'ordre pour le fabricant.
- `<invoke>` asynchrone vers Manufacturer (`requestOrder`).
- `<flow>` avec deux `<receive>` parallèles : `receiveManufacturingStatus` et `receiveShippingStatus`.
- Lorsque les deux messages sont reçus, le processus se termine (commande complète).

*(Alternative : `<pick>` avec deux `<onMessage>` si l'on préfère un modèle basé sur événements.)*

## 6. Fichiers `deploy.xml` (Apache ODE)
Chaque processus déclare :
- `<provide>` pour le service exposé (endpoint Tomcat/ODE).
- `<invoke>` pour les services distants (URL d'autres processus).
Vérifier que les namespaces des services pointent vers les WSDL stockés dans `wsdl/`.

## 7. Dockerisation complète

### 7.1 `docker/Dockerfile.ode`
- Base `tomcat:9-jdk11`.
- Télécharge `apache-ode-war-1.3.9` et le déploie sous `webapps/ode.war`.
- Copie `processes/` et `wsdl/` dans le conteneur (ou monte en volume pour le dev).

### 7.2 `docker/Dockerfile.soapui-cli`
- Base `smartbear/soapuios-testrunner:5.7.0`.
- Monte `tests/` et exécute `testrunner.sh` contre le projet SoapUI.

### 7.3 `docker/docker-compose.yml`
```
version: "3.9"
services:
  ode:
    build:
      context: ..
      dockerfile: docker/Dockerfile.ode
    container_name: ode-bpel
    ports:
      - "8080:8080"
    volumes:
      - ../processes:/ode/apache-ode-1.3.9/webapps/ode/WEB-INF/processes
      - ../wsdl:/ode/contracts

  soapui:
    build:
      context: ..
      dockerfile: docker/Dockerfile.soapui-cli
    container_name: soapui-cli
    depends_on:
      - ode
    command: ["testrunner.sh", "/tests/StoreProcess-soapui-project.xml"]
    volumes:
      - ../tests:/tests
```

Lancer `docker compose up --build`. ODE écoute sur `http://localhost:8080/ode`.

## 8. Test du scénario
1. Démarrer l'ensemble (`docker compose up`).
2. Dans SoapUI (ou `soapui-cli`), invoquer `startRestock` sur le service Store.
3. Observer les logs (`docker logs -f ode-bpel`) :
   - StoreProcess démarre puis attend dans le `<flow>`.
   - ManufacturerProcess démarre, attend 30s, invoque Shipper et notifie Store.
   - ShipperProcess démarre, attend 15s, notifie Store.
4. Lorsque Store reçoit les deux messages, l'instance se termine.

## 9. Prochaines étapes
- Ajouter des validations XSD côté `<assign>` via `<validate>` si nécessaire.
- Étendre les WSDL avec des fautes (`fault` message) pour couvrir les erreurs.
- Ajouter des tests SoapUI couvrant des chemins d'erreur (transporteur indisponible, etc.).
- Automatiser la génération des packages ODE (ZIP) pour déploiement CI/CD.

Bonne construction de votre chorégraphie BPEL !
