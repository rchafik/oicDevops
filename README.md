# OIC e OCI DevOps - Exemplos para sua esteira CI/CD

## Objetivo

Neste documento vamos abordar como trabalhar com APIs de Desenvolvimento do **OIC** e um exemplo de como implementar uma chamada de API numa esteira de CI/CD utilizando o **OCI DevOps**.

![capa](images/00_capa_artigo.png "capa")

### OIC:
- como acionar as APIs de Desenvolvimento do Oracle Integration Cloud (OIC);
- como configurar um confidential application e o que é necessário para acionar as APIs de Desenvolvimeno do OIC;
- como realizar o export de um projeto OIC;
- como configurar, ativar e testar uma conexão;
- como ativar e testar sua integração;
- como importar um projeto OIC.

### OCI DevOps:
- deploy de um arquivo CAR do OIC pelo OCI DevOps, acionando as APIs de Desenvolvimento do OIC;
- detalhes sobre o produto OCI DevOps;
- como configurar um repositório GIT e extrair um arquivo `.CAR`, que é um deploy de um projeto OIC;
- detalhes sobre pipeline de build e pipeline de deploy;
- exemplo de como realizar o import de um arquivo `.CAR` para o OIC;
- exemplo de Shell Script para extrair o arquivo do Artifact Registry e importar via API do OIC.

## Safe Harbor

> **IMPORTANTE**: Esse conteúdo foi desenvolvido exclusivamente para fins educacionais e de estudo. Ele fornece um ambiente para que aprendizes possam experimentar e adquirir experiência prática em um cenário controlado. É importante destacar que as configurações e práticas de segurança utilizadas neste laboratório podem não ser adequadas para cenários do mundo real. As considerações de segurança para aplicações reais costumam ser muito mais complexas e dinâmicas. Portanto, antes de implementar qualquer uma das técnicas ou configurações demonstradas aqui em um ambiente de produção, é essencial realizar uma avaliação e revisão de segurança abrangente. Essa revisão deve incluir todos os aspectos de segurança, como controle de acesso, criptografia, monitoramento e conformidade, garantindo que o sistema esteja alinhado com as políticas e padrões de segurança da organização. A segurança deve sempre ser uma prioridade máxima ao fazer a transição de um ambiente de laboratório para uma implementação no mundo real.

## Pré-requisitos

- ter um tenancy OCI;
- uma instância do OIC;
- um Bucket configurado, porque iremos construir uma integração no OIC para listar os arquivos (objetos) deste bucket;
- uma conta no [GitHub](https://github.com/), que será utilizado neste exemplo;
- criar um projeto no OCI DevOps, para configurarmos nossa esteira de deploy do OIC;
- curl, jq, OpenSSL e OCI CLI configurados.

## Informações para acionarmos as APIs do OIC

Antes de usar as APIs do OIC, configure a autenticação OAuth através do IAM seguindo a documentação [Call the Developer APIs with Client Credentials](https://docs.oracle.com/en/cloud/paas/application-integration/integrations-user/call-developer-apis-client-credentials.html).

Vamos precisar das seguintes informações para acionar as APIs do OIC:
- endpoint do seu ambiente IAM (Identity & Security -> Domains -> Escolha o seu domínio -> Details -> Domain URL)
- endpoint de design do seu ambiente OIC (Developer Services -> Application Integration -> Integration -> Escolha a sua instância do OIC -> Details -> Design-time URL)
- scope do ambiente OIC (O scope do seu ambiente OIC que foi adicionado na Confidential Application que possui `/ic/api/`)
- Client ID (informação da sua Confidential Application)
- Client Secret (informação da sua Confidential Application)

>Atenção

Devemos gerar a informação para autenticação (Header de Authorization) em base64 concatenando [Client ID + : + Client secret] da Confidential Application que foi criada no IAM.

```bash
echo -n "Client ID:Client Secret" | openssl enc -base64 -A
```

## Visão geral do fluxo para configurar o OIC

1. Extrair o artefato CAR do ambiente de origem
2. Importar o CAR no ambiente de destino
3. Configurar conexões necessárias
4. Validar / testar as conexões
5. Ativar a integração
6. Testar a Integração

## Fluxo visual de uso das APIs do OIC

```mermaid
flowchart LR
  OICOrig[OIC Origem]
  Pipeline[APIs OIC]
  OICDest[OIC Destino]

  OICOrig -->|export CAR| Pipeline
  Pipeline -->|import CAR| OICDest

  Pipeline -->|configure connection| Configure[Configure Connection]
  Pipeline -->|test connection| TestConn[Test Connection]
  Pipeline -->|activate integration| Activate[Activate Integration]
  Pipeline -->|test integration| TestInt[Test Integration]

  Configure --> OICDest
  TestConn --> OICDest
  Activate --> OICDest
  TestInt --> OICDest
```

## Preparar o ambiente OIC

Para realizarmos os testes:

1. Importe o arquivo [LAB-DEVOPS-DEPLOY001.car](https://github.com/rchafik/oicDevops/blob/main/deployments/LAB-DEVOPS-DEPLOY001.car) no seu ambiente OIC:

  Projects -> Clique no botão `Add` -> Utilize a Opção Import (Upload a CAR File)

Com isso, teremos o projeto `labDevOps` importado.

![projeto importado no oic](images/01_oic_import_car_file.png "projeto importado no oic")

2. Configure a conexão **BUCKET**: 

![Bucket Connection](images/02_oic_bucket_connection.png "Bucket Connection")

- De acordo com a sua região da OCI, escolha o endpoint adequado para o Bucket conforme documentação [Object Storage Service API](https://docs.oracle.com/en-us/iaas/api/#/en/objectstorage/20160918/);
- Preencha todas as informações necessárias para conexão;
- Teste e Salve a conexão.

Em caso de problemas, consulte esses documentos:

  - [Troubleshoot the REST Adapter](https://docs.oracle.com/en/cloud/paas/application-integration/rest-adapter/troubleshoot-rest-adapter.html) 
  - [Invoke Oracle Cloud Infrastructure Object Storage from an Integration with an OCI Object Storage Action](https://docs.oracle.com/en/cloud/paas/application-integration/integrations-user/invoke-object-storage-oci-object-storage-action.html)

3. Ative e Teste a integração 

![Integration Test](images/03_oic_integration_test.png "Integration Test")

- Na integração `INT001_COUNT_BUCKET_OBJECTS` utilizamos a API [ListObjects](https://docs.oracle.com/en-us/iaas/api/#/en/objectstorage/20160918/Object/ListObjects) `GET /n/{namespaceName}/b/{bucketName}/o`
- Ela é uma integração que recebe apenas dois URI parameters:
  - namespace: namespace do bucket;
  - bucket: nome do bucket;
- Ela retorna a quantidade de objetos existentes no bucket informado:

  ```json
  {
    "objects" : 11
  }
  ```

4. Crie um Deploy

No OIC criamos o deploy chamado `DEPLOY001`, selecionando a integração que ativamos no passo anterior:

![Deploy](images/04_oic_deploy.png "Deploy")

## Etapas de uso das APIs do OIC

### 1. Extrair um CAR do ambiente de Origem do OIC

A exportação do arquivo CAR será baseada no deploy criado, no qual selecionamos os artefatos que fazem parte dele.

Utilize a API [Export a Project](https://docs.oracle.com/en/cloud/paas/application-integration/rest-api/op-ic-api-integration-v1-projects-id-archive-post.html) para gerar o arquivo CAR:

```bash
ACCESS_TOKEN=$(curl -s --request POST \
  --url https://your-idcs.identity.oraclecloud.com/oauth2/v1/token \
  --header 'Authorization: Basic BASE64-YOUR_CREDENTIALS' \
  --header 'content-type: application/x-www-form-urlencoded;charset=UTF-8' \
  --data 'grant_type=client_credentials&scope=https://YOUR-OIC-SCOPE.integration.sa-saopaulo-1.ocp.oraclecloud.com:443/ic/api/' | jq -r '.access_token'); 
  echo "The access_token is: " $ACCESS_TOKEN


curl --fail-with-body -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d @request_payload.json \
  -o LAB-DEVOPS-DEPLOY001.car \
  "https://design.integration.sa-saopaulo-1.ocp.oraclecloud.com/ic/api/integration/v1/projects/YOUR-PROJECT/archive?integrationInstance=your-oic-instance"
```

O arquivo `request_payload.json` deve conter as seguintes informações:
  - type: DEVELOPED, informação fixa;
  - code: o identificador do seu projeto;
  - label: o identificador do seu deploy.

Para o nosso exemplo:

```json
{
  "type": "DEVELOPED",
  "code": "LAB-DEVOPS",
  "label" : "DEPLOY001"
}
```

O arquivo `LAB-DEVOPS-DEPLOY001.car` será gerado no diretório onde o comando curl foi executado.

### 2. Importar o CAR no ambiente Destino

Para importar o arquivo na instância de destino do OIC, devemos utilizar a API [Import (Add) a Project](https://docs.oracle.com/en/cloud/paas/application-integration/rest-api/op-ic-api-integration-v1-projects-archive-post.html):

```bash
ACCESS_TOKEN=$(curl -s --request POST \
  --url https://your-idcs.identity.oraclecloud.com/oauth2/v1/token \
  --header 'Authorization: Basic BASE64-YOUR_CREDENTIALS' \
  --header 'content-type: application/x-www-form-urlencoded;charset=UTF-8' \
  --data 'grant_type=client_credentials&scope=https://YOUR-OIC-SCOPE.integration.sa-saopaulo-1.ocp.oraclecloud.com:443/ic/api/' | jq -r '.access_token');  
  echo "The access_token is: " $ACCESS_TOKEN

curl -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F file=@LAB-DEVOPS-DEPLOY001.car -F type=application/octet-stream \
  "https://design.integration.sa-saopaulo-1.ocp.oraclecloud.com/ic/api/integration/v1/projects/archive?integrationInstance=your-oic-instance"
```

O retorno esperado é esse: 

```json
{
  "cloneRestrict": "NONE",
  "code": "LAB-DEVOPS",
  "id": "LAB-DEVOPS",
  "links": [
    {
      "href": "https://design.integration.sa-saopaulo-1.ocp.oraclecloud.com/ic/api/integration/v1/projects/LAB-DEVOPS?integrationInstance=your-oic-instance",
      "rel": "self"
    },
    {
      "href": "https://design.integration.sa-saopaulo-1.ocp.oraclecloud.com/ic/api/integration/v1/projects/LAB-DEVOPS?integrationInstance=your-oic-instance",
      "rel": "canonical"
    }
  ],
  "mcpEnabled": false,
  "name": "labDevOps",
  "origin": {},
  "simplifiedMode": false,
  "smartTags": [
    "app:rest",
    "style:app driven orchestration"
  ],
  "state": {
    "assets": {
      "labelsRs": {
        "items": [
          {
            "code": "DEPLOY001",
            "integrations": [
              {
                "code": "INT001",
                "version": "01.00.0000"
              }
            ],
            "lastUpdated": "2026-09-17T19:23:49.887+0000",
            "name": "deploy001"
          }
        ]
      }
    },
    "created": {
      "by": "091e196a37b849a6918e0df40d77fb39",
      "date": "2026-09-17T19:23:49.872+0000"
    },
    "latest": {
      "by": "091e196a37b849a6918e0df40d77fb39",
      "date": "2026-09-17T19:23:49.872+0000"
    },
    "projectRevisionId": 0,
    "serviceInstanceId": 0,
    "status": "DRAFT",
    "updated": {
      "by": "091e196a37b849a6918e0df40d77fb39",
      "date": "2026-09-17T19:23:49.872+0000"
    }
  },
  "type": "DEVELOPED",
  "viewRestricted": false
}
```

O projeto será criado no OIC de destino:

![Project imported](images/10_oic_project_imported.png "Project Imported")


Com o arquivo .CAR importado, podemos observar que a conexão `BUCKET` está com o status `Draft`.
Isso significa que precisamos informar todos os dados necessários para configurar e testar a conexão, antes de ativarmos a integração.

![Draft Connection](images/11_oic_project_connection_draft.png "Draft Connection")

### 3. Configurar uma conexão

Para configurar uma conexão, devemos utilizar a API [Update a Connection in a Project](https://docs.oracle.com/en/cloud/paas/application-integration/rest-api/op-ic-api-integration-v1-projects-projectid-connections-id-post.html).

No exemplo que vamos configurar, utilizaremos uma conexão REST com a política de segurança `OCI_SIGNATURE_VERSION1`, para conectividade com um Bucket da OCI.

>Sugestão para configurar o payload

  Consultamos uma conexão existente e já configurada via console do OIC, realizando **GET** na API, e analisamos o payload retornado, para servir de exemplo na configuração da conexão em outro ambiente.



```bash
ACCESS_TOKEN=$(curl -s --request POST \
  --url https://your-idcs.identity.oraclecloud.com/oauth2/v1/token \
  --header 'Authorization: Basic BASE64-YOUR_CREDENTIALS' \
  --header 'content-type: application/x-www-form-urlencoded;charset=UTF-8' \
  --data 'grant_type=client_credentials&scope=https://YOUR-OIC-SCOPE.integration.sa-saopaulo-1.ocp.oraclecloud.com:443/ic/api/' | jq -r '.access_token');
  echo "The access_token is: " $ACCESS_TOKEN


curl --fail-with-body -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-HTTP-Method-Override:PATCH" \
  -d @request_payload_conexao_BUCKET.json \
  "https://design.integration.sa-saopaulo-1.ocp.oraclecloud.com/ic/api/integration/v1/projects/LAB-DEVOPS/connections/BUCKET?integrationInstance=your-oic-instance"
```

Exemplo do arquivo `request_payload_conexao_BUCKET.json`:

```json
{
   "connectionProperties": 
   [
      {
         "propertyGroup": "CONNECTION_PROPS",
         "propertyName": "connectionType",
         "propertyType": "CHOICE",
         "propertyValue": "restUrl"
      },

      {
         "propertyGroup": "CONNECTION_PROPS",
         "propertyName": "connectionUrl",
         "propertyType": "URL",
         "propertyValue": "https://objectstorage.sa-saopaulo-1.oraclecloud.com"
      }
   ],
   "securityPolicy": "OCI_SIGNATURE_VERSION1",
   "securityProperties":    [
      {
         "propertyGroup": "CREDENTIALS",
         "propertyName": "TenancyOCID",
         "propertyType": "STRING",
         "propertyValue": "ocid1.tenancy.oc1..AAA"
      },
      {
         "propertyGroup": "CREDENTIALS",
         "propertyName": "UserOCID",
         "propertyType": "STRING",
         "propertyValue": "ocid1.user.oc1..AAA"
      },

      {
         "propertyGroup": "CREDENTIALS",
         "propertyName": "FingerPrint",
         "propertyType": "STRING",
         "propertyValue": "your-finger-print"
      }
   ]
}
```

Neste caso, para concluir a configuração da conexão há uma propriedade, Private Key, que precisa de um arquivo do tipo PEM. 
Precisamos utilizar a API [Upload Connection Property Attachment in a Project](https://docs.oracle.com/en/cloud/paas/application-integration/rest-api/op-ic-api-integration-v1-projects-projectid-connections-id-attachments-connpropname-post.html):

> Atenção
  Esse comando demora alguns instantes, por favor, tenha paciência!

  Não mantenha a conexão aberta na console do OIC durante a execução dos comandos pela API, pois isso pode bloquear a atualização e causar erros.

```bash
ACCESS_TOKEN=$(curl -s --request POST \
  --url https://your-idcs.identity.oraclecloud.com/oauth2/v1/token \
  --header 'Authorization: Basic BASE64-YOUR_CREDENTIALS' \
  --header 'content-type: application/x-www-form-urlencoded;charset=UTF-8' \
  --data 'grant_type=client_credentials&scope=https://YOUR-OIC-SCOPE.integration.sa-saopaulo-1.ocp.oraclecloud.com:443/ic/api/' | jq -r '.access_token'); 
  echo "The access_token is: " $ACCESS_TOKEN


curl -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F file=@your-file.pem -F type=application/octet-stream \
  "https://design.integration.sa-saopaulo-1.ocp.oraclecloud.com/ic/api/integration/v1/projects/LAB-DEVOPS/connections/BUCKET/attachments/PrivateKey?integrationInstance=your-oic-instance"
```


### 4. Testar a conexão

Após o preenchimento de todas as informações obrigatórias para a **conexão**, será necessário testar a **conexão** utilizando a API [Test a Connection in a Project](https://docs.oracle.com/en/cloud/paas/application-integration/rest-api/op-ic-api-integration-v1-projects-projectid-connections-id-test-post.html):


```bash
curl -X POST -H "Authorization: Bearer $ACCESS_TOKEN" \
-H "Content-Type:application/json" \
"https://design.integration.sa-saopaulo-1.ocp.oraclecloud.com/ic/api/integration/v1/projects/LAB-DEVOPS/connections/BUCKET/test?integrationInstance=your-oic-instance"
```

Resultado esperado:

```json
{"details":"Test of BUCKET connection succeeded.","id":"BUCKET","status":"SUCCESS"}
```

### 5. Ativar a integração

Para iniciar o processo de ativação da integração, que precisa estar com o status = `CONFIGURED`, utilize a API [Update an Integration in a Project](https://docs.oracle.com/en/cloud/paas/application-integration/rest-api/op-ic-api-integration-v1-projects-projectid-integrations-id-post.html):

```bash
curl -X POST -H "Authorization: Bearer $ACCESS_TOKEN" \
-H "Content-Type:application/json" \
-H "X-HTTP-Method-Override:PATCH" \
-d @activate.json \
"https://design.integration.sa-saopaulo-1.ocp.oraclecloud.com/ic/api/integration/v1/projects/LAB-DEVOPS/integrations/INT001%7C01.00.0000?integrationInstance=your-oic-instance"
```

Exemplo do arquivo `activate.json`:

```json
{"status":"ACTIVATED"}
```

Retorno esperado: 

```json
{
   "apiDeploymentInprogress":false,
   "compatible":false,
   "links":[
      
   ],
   "lockedFlag":false,
   "scheduleApplicableFlag":false,
   "scheduleDefinedFlag":false,
   "softDeactivated":false,
   "status":"ACTIVATION_INPROGRESS",
   "tempCopyExists":false,
   "totalEndPoints":0
}
```

Para se certificar de que a integração foi ativada, podemos consultar a API [Retrieve Integration Activation Status in a Project](https://docs.oracle.com/en/cloud/paas/application-integration/rest-api/op-ic-api-integration-v1-projects-projectid-integrations-id-activationstatus-get.html):

```bash
curl -X GET -H "Authorization: Bearer $ACCESS_TOKEN" \
-H "Content-Type:application/json" \
"https://design.integration.sa-saopaulo-1.ocp.oraclecloud.com/ic/api/integration/v1/projects/LAB-DEVOPS/integrations/INT001%7C01.00.0000/activationStatus?integrationInstance=your-oic-instance"
```

Resultado esperado: 

```json
{"activationStatus":"ACTIVATED"}
```

### 6. Testar a integração

Para testarmos a integração, precisamos das seguintes informações:
- scope que consta na confidential application que possui `urn:opc:resource:consumer::all`;
- o endpoint de runtime do OIC.

```bash
ACCESS_TOKEN=$(curl -s --request POST \
  --url https://your-idcs.identity.oraclecloud.com/oauth2/v1/token \
  --header 'Authorization: Basic BASE64-YOUR_CREDENTIALS' \
  --header 'content-type: application/x-www-form-urlencoded;charset=UTF-8' \
  --data 'grant_type=client_credentials&scope=your-oic-scopeurn:opc:resource:consumer::all' | jq -r '.access_token'); 
  echo "The access_token is: " $ACCESS_TOKEN

curl -X GET -H "Authorization: Bearer $ACCESS_TOKEN" \
"https://your-runtime-oic-endpoint.oraclecloud.com/ic/api/integration/v2/flows/rest/project/LAB-DEVOPS/INT001/1.0/bucketNameSpace/BucketName"
```

Resultado esperado, com a quantidade de objetos que existem no seu bucket:

```json
{
  "objects" : 11
}
```

Tela de monitoramento do OIC com as execuções bem-sucedidas da integração:

![Observe](images/12_oic_integration_status.png "Observe")

## Sobre o OCI DevOps

O OCI DevOps é o serviço de CI/CD gerenciado da Oracle Cloud Infrastructure. 
Ele permite criar pipelines automatizados para build, teste e deploy de aplicações e integrações.

- Artifact: é o pacote de saída produzido pela etapa de build. No contexto do OIC, um artefato pode ser um arquivo CAR, um pacote ZIP ou qualquer bundle que será consumido pelo deploy.
- Build: etapa em que o código ou integração é compilado, testado e empacotado. O build produz o artifact que será usado pelo deploy.
- Deploy: etapa em que o artifact é aplicado no ambiente alvo. Para OIC, neste exemplo a etapa realiza a importação do CAR via API do OIC.
- Shell stage: stage que executa comandos shell (bash) ou scripts em um ambiente controlado, ideal para automações como chamadas `curl`, transformação de arquivos ou invocação de utilitários.

### Exemplo de Esteira OCI DevOps para o OIC

![oci devops](images/00_fluxo_oci_devops.png "oci devops")

 O objetivo é servir como referência para reutilização em outros projetos.

#### Visão Geral da Solução

A esteira implementa o fluxo abaixo:

1. O código-fonte do projeto OIC fica em um repositório GitHub externo.
2. O stage de build seleciona um arquivo `.car` existente no repositório, copia-o para `out/project.car` e o disponibiliza como artefato de saída.
3. O stage de entrega publica esse arquivo como Generic Artifact no OCI Artifact Registry.
4. O stage de trigger inicia uma deployment pipeline e repassa os parâmetros exportados no build.
5. A deployment pipeline executa um Shell stage com command spec.
6. Esse Shell stage baixa o `.car` do Artifact Registry, obtém um token OAuth do OIC e executa o import do projeto via API.
7. O projeto DevOps envia notificações para um tópico OCI Notifications associado ao projeto.


```mermaid
flowchart LR
    GH["GitHub\nrchafik/oic\nbranch: main"]
    CONN["External Connection\ngithub-oic"]
    BP["Build Pipeline\noicBuildPipeline"]
    S1["Stage 1\nBUILD\nbuild-oic-github\nbuild_spec_oic.yaml"]
    S2["Stage 2\nDELIVER_ARTIFACT\ndeployOIC"]
    AR["Artifact Registry\nGeneric Artifact\nartifact-repository-oic"]
    S3["Stage 3\nTRIGGER_DEPLOYMENT_PIPELINE\ndeployOIC"]
    DP["Deployment Pipeline\ndeployOIC"]
    DA["Command Spec Artifact\ndeployOIC-CommandSpecification"]
    SH["Shell Stage\ndeployOIC\nCI.Standard.E4.Flex"]
    VAULT["OCI Vault Secret\nOIC_BASIC_AUTH_B64"]
    OAUTH["OAuth Token Endpoint"]
    OIC["Oracle Integration Cloud\nImport Project API"]
    TOPIC["OCI Notifications Topic\ntopicOIC"]

    GH --> CONN
    CONN --> BP
    BP --> S1
    S1 -->|"output artifact\noic-project-car"| S2
    S2 -->|"ARTIFACT_PATH\nARTIFACT_VERSION"| AR
    S2 --> S3
    S3 -->|"pass all parameters"| DP
    DP --> DA
    DP --> SH
    AR --> SH
    VAULT --> SH
    SH --> OAUTH
    OAUTH --> SH
    SH --> OIC
    BP -. eventos .-> TOPIC
    DP -. eventos .-> TOPIC
```

O diagrama acima representa a topologia lógica da esteira e ajuda a explicar como o artifact binário, os parâmetros exportados e o command spec se conectam entre build e deploy.

Vamos utilizar e configurar os seguintes recursos:

- `Notifications Topic`: canal de notificação associado ao projeto DevOps para eventos operacionais.
- `DevOps Project`: agrupador lógico dos recursos de CI/CD.
- `External Connection`: credencial e vínculo para acesso ao repositório GitHub.
- `Build Pipeline`: pipeline responsável por selecionar, validar e publicar o `.car`.
- `Build Spec`: arquivo YAML com os comandos executados no build runner.
- `Generic Artifact`: artefato binário publicado no OCI Artifact Registry.
- `Deployment Pipeline`: pipeline responsável por consumir o artefato e executar o deploy.
- `Shell Stage`: stage de deploy que executa comandos customizados em uma container instance.
- `Command Spec`: arquivo YAML com os comandos do Shell stage.

## Criação da esteira no OCI DevOps

### 0. Tópico e Projeto

Antes de iniciarmos no OCI DevOps, primeiro devemos ter um **topic** criado:

  - Developer Services -> Notifications -> Notifications -> Topics

![topic](images/21_topic.png "topic")

> The Notifications service helps you broadcast messages to distributed components through a publish-subscribe pattern. Use Notifications to get notified when event rules are triggered or alarms are breached, or to directly publish a message. A topic is a communication channel for sending messages to the subscriptions in the topic.

Agora precisamos criar um projeto e utilizar o topic gerado anteriormente:

- Developer Services -> DevOps -> Projects

![project](images/22_project.png "project")

### 1. Criando o External Connection

Uma vez criado o Projeto no OCI DevOps, primeiro iremos criar um External Connection para se conectar ao SCM (GitHub, GitLab ou Bitbucket). É necessário também ter gerado um Token no SCM para acesso ao repositório e criar um `Vault` e depois `Secret` para guardar o seu Token.

- Ir em `External Connections` e depois em `Create External Connections`

![external connection](images/01_devops.png "external connection devops")

Colocar o `Name`,  escolher o `Type` e o `Vault e Secret` onde está o Token.

![external connection](images/02_devops.png "external connection devops")

Após a criação fazer um `Validate Connection` para verificar se o OCI DevOps está conectado ao seu repositório de código.

![external connection validate](images/03_devops.png "external connection devops validate")

### 2. Criando o repositório de artefato

Primeiro vamos em um serviço fora do OCI DevOps:
- `Developer Services` -> `Artifact Registry` -> `Create repository`.

![Artifact Registry](images/23_artifact_registry.png "Artifact Registry")

Copie o OCID deste repositório, que iremos utilizar a seguir.

> O stage de entrega publicará o arquivo `.car` neste repositório.

Após a criação do `Artifact Registry` voltaremos ao projeto no OCI DevOps.

Em `Latest artifacts` -> `Add Artifact`. Informar o `Nome` e no `Artifact Type` colocar `General artifact`.
No `Artifact Source` utilize a opção `OCI Artifact Registry`.
Copie o OCID do passo anterior, algo como `ocid1.artifactrepository.oc1.sa-saopaulo-1.0.xyz`, para o atributo `Artifact Registry repository`.

Em `Artifact Location`, escolha `Enter a path and version`, informando os seguintes parâmetros:

- `Artifact Path: ${ARTIFACT_PATH}`
- `Version: ${ARTIFACT_VERSION} `

Conforme a imagem abaixo:

![artifact](images/04_devops.png "artifact")

Após a criação do Artefato vamos criar a nossa esteira de build.


### 3. Criando o Build Pipeline

Nessa parte iremos criar dois stages: 
- o primeiro seleciona o arquivo `.car` através do nosso arquivo [build_spec_oic.yaml](build_spec_oic.yaml);
- o segundo faz a entrega desse artefato no repositório criado no passo anterior.

#### 3.1 Criando o Build Pipeline

Ir em `Latest Build Pipelines` -> `Create Build Pipeline`, utilize o nome **oicBuildPipeline**:

![build pipeline](images/24_create_build_pipeline.png "build pipeline")

Entre no Build pipeline criado e clique no símbolo de `+` para adicionar um stage `Managed Build`.

Nessa parte é onde escolhemos o shape da máquina que irá fazer o build, neste caso podemos utilizar o **Default Shape**.

O arquivo de `build_spec` tem o seguinte nome: `build_spec_oic.yaml`. 

Em `Primary code repository` vamos selecionar o `External Connection` que criamos no passo 1, informando o repositório e a branch utilizada, e clicar no botão `Add`.

![stage](images/25_build_pipeline_stage1.png "stage")

Nesse momento iremos criar o segundo stage para fazer a entrega do binário `.car` no registry criado no passo 2.

![artifact](images/06_devops.png "artifact")

Ir em `Add Stage` -> escolher `Delivery artifacts`

![delivery](images/07_devops.png "delivery")

Ir em `Select artifacts` -> `Incluir o artefato criado no passo 2` -> Ir em `Add Stage` -> `Add`

Na parte de `Build config/result artifact name`, colocar `oic-project-car`.
  > O valor **oic-project-car** informado no atributo `Build config/result artifact name` deve corresponder ao nome do artefato de saída definido em `build_spec_oic.yaml`. Esse artefato aponta para `out/project.car`, uma cópia do CAR selecionado no repositório.

![send car to artifact](images/26_build_pipeline_stage2.png "send car to artifact")

#### 3.2 Habilitar Log e Testes Iniciais

Antes de iniciarmos alguns testes iniciais, precisamos habilitar o log:

![log](images/28_log.png "log")

Neste momento nosso **build pipeline** está desta forma:

![build pipeline](images/27_build_pipeline.png "build pipeline")

Acesse a aba **Parameters** para informar o nome do arquivo CAR que será utilizado no build:
  - Name: CAR_FILE_NAME
  - Default value: LAB-DEVOPS-DEPLOY001.car

Voltando para a aba **Build pipeline**, vamos clicar no botão `Start manual run`.

Assim, confirmamos que todas as configurações feitas até agora estão funcionando:

![build pipeline tests](images/29_build_pipeline_tests.png "build pipeline tests")

O arquivo do repositório git foi entregue ao **Artifact Registry**:

![car file entregue](images/30_car_file_gerado_artifacty_registry.png "car file entregue")

### 4. Criando a Deployment Pipeline

A `Deployment Pipeline` será responsável por consumir o `.car` publicado no Artifact Registry e executar o arquivo de comandos `import_oic.yaml`.

Ir em `Latest deployment pipelines` -> `Create Pipeline`.

Preencher:

- `Name`: nome da pipeline de deploy, por exemplo `deployOIC`;
- `Description`: descrição opcional;

Depois de criar a pipeline, adicionar os parâmetros que serão recebidos da build:

- `ARTIFACT_PATH`
- `ARTIFACT_VERSION`

> Esses dois parâmetros precisam ter exatamente os mesmos nomes exportados no arquivo [build_spec_oic.yaml](build_spec_oic.yaml). Eles serão usados pelo [import_oic.yaml](import_oic.yaml) para baixar o arquivo `.car` correto do Artifact Registry.

![criação do pipeline](images/13_oic_create_deployment.png "criação do pipeline")

Ir em `Parameters` e adicionar o `ARTIFACT_PATH` e `ARTIFACT_VERSION`.

![criação do pipeline](images/14_parameters.png "criação do pipeline")


### 5. Preparando o Artifact do tipo Command specification

O arquivo [import_oic.yaml](import_oic.yaml) executa três ações principais:

1. baixa o `.car` do Artifact Registry usando `ARTIFACT_PATH` e `ARTIFACT_VERSION`;
2. obtém um token OAuth no IAM usando a secret `OIC_BASIC_AUTH_B64`;
3. importa o projeto no OIC chamando a API `/ic/api/integration/v1/projects/archive`.

Prepare o seu arquivo baseado no `import_oic.yaml`, substituindo os placeholders pelos valores específicos do ambiente:

- `TOKEN_URL`: endpoint OAuth do domínio IAM;
- `OIC_SCOPE`: scope do OIC para uso das Developer APIs;
- `OIC_HOST`: endpoint design-time do OIC;
- `OIC_INSTANCE`: nome da instância OIC;
- `ARTIFACT_REPOSITORY_ID`: OCID do repositório no OCI Artifact Registry;
- `OIC_BASIC_AUTH_B64`: OCID da secret no Vault que guarda o valor em **base64** de `Client ID:Client Secret`.

  > Essa secret deverá ser criada com o conteúdo gerado pelo comando openssl, citado anteriormente para o consumo das APIs do OIC.

### 6. Criando o Shell Stage de Importação no OIC

Vamos voltar para o Deployment Pipeline criado no passo 4 e adicionar um stage do tipo `Shell`.

Ir em `Add Stage` -> `Shell`.

![shell](images/16_shell.png "shell")

Preencher:

- `Stage name`: `deployOIC`;

- `Command spec artifact`: vamos clicar no botão **Select artifact** e depois teremos a opção para criar o **Artefato**:
  - Name: deployOIC-CommandSpecification;
  - Type: Command specification;
  - Artifact source: inline; cole o conteúdo do `import_oic.yaml` já ajustado com os valores do ambiente;
  - Allow parametrization: desabilitado.

    ![command spec](images/15_command_spec.png "command spec")

- `Shape`: selecionar um shape compatível com Shell stage, por exemplo `CI.Standard.E4.Flex`;
- `OCPUs` e `Memory`: definir conforme o padrão do ambiente. Para este exemplo, `1 OCPU` e `1 GB` são suficientes;
- `Network`: selecionar a VCN, subnet e NSG, se aplicável, com saída para o endpoint do IAM, para o Artifact Registry e para o endpoint design-time do OIC;
- `Timeout`: definir tempo suficiente para download do artifact, autenticação e importação do `.car`.

Esse stage executará o `import_oic.yaml` em um container instance gerenciado pelo OCI DevOps. 
O OCI CLI já fica disponível no runtime do Shell stage e usa o resource principal do pipeline para acessar recursos OCI.

![edit stage](images/17_import_oic_stage.png "edit stage")

### 7. Validando IAM, Vault e Rede

Crie um dynamic group para os pipelines de build e deploy da esteira. A regra abaixo inclui os pipelines `oicBuildPipeline` e `deployOIC` pelos seus OCIDs, delimitando quais recursos receberão as permissões IAM.

Substitua os valores abaixo pelos OCIDs da tenancy e dos pipelines criados nos passos 3 e 4. Os OCIDs dos pipelines estão disponíveis nas respectivas páginas de detalhes.

```bash
TENANCY_OCID="<ocid-da-tenancy>"
BUILD_PIPELINE_OCID="<ocid-do-pipeline-oicBuildPipeline>"
DEPLOY_PIPELINE_OCID="<ocid-do-pipeline-deployOIC>"

oci iam dynamic-group create \
  --profile DEFAULT \
  --compartment-id "$TENANCY_OCID" \
  --name "dg-oic-devops" \
  --description "Pipelines de build e deploy da esteira OIC" \
  --matching-rule "ANY {
    resource.id = '${BUILD_PIPELINE_OCID}',
    resource.id = '${DEPLOY_PIPELINE_OCID}'
  }"
```

Nesse comando, `--compartment-id` recebe o OCID da tenancy, que corresponde ao compartimento raiz. Confirme que o dynamic group `dg-oic-devops` está no estado `ACTIVE` antes de utilizá-lo. Consulte a [referência do comando de criação](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/dynamic-group/create.html) e a [documentação das regras de associação](https://docs.oracle.com/en-us/iaas/Content/Identity/dynamicgroups/Writing_Matching_Rules_to_Define_Dynamic_Groups.htm).

O dynamic group identifica os pipelines que receberão as permissões definidas nas policies. No Shell stage, o OCI CLI utiliza a identidade do pipeline de deploy para acessar os recursos OCI. A autenticação nas APIs do OIC continua sendo realizada pelo token OAuth configurado no exemplo. Consulte a [documentação do Shell stage](https://docs.oracle.com/en-us/iaas/Content/devops/using/shell_stage.htm).

> Se os pipelines forem excluídos e recriados, atualize os OCIDs na regra do dynamic group.

Antes de executar a esteira, validar as permissões necessárias para o OCI DevOps:

- acesso à secret do Vault usada em `OIC_BASIC_AUTH_B64`;
- acesso de leitura ao Artifact Registry usado pelo `ARTIFACT_REPOSITORY_ID`;
- permissão para criar/executar os recursos temporários do Shell stage, como container instances, containers e VNICs;
- permissão de uso da subnet, DHCP options e NSG, quando usado;
- saída de rede para o `TOKEN_URL`, `OIC_HOST` e Artifact Registry.

As policies abaixo referenciam o dynamic group pelo nome `dg-oic-devops`, definido no comando de criação. Substitua `<compartment>` pelo nome do compartimento ao qual cada permissão se aplica:

```text
Allow dynamic-group dg-oic-devops to manage devops-family in compartment <compartment>
Allow dynamic-group dg-oic-devops to read secret-family in compartment <compartment>
Allow dynamic-group dg-oic-devops to read all-artifacts in compartment <compartment>
Allow dynamic-group dg-oic-devops to manage generic-artifacts in compartment <compartment-artifact-registry>
Allow dynamic-group dg-oic-devops to use ons-topics in compartment <compartment-notifications>
Allow dynamic-group dg-oic-devops to manage compute-container-instances in compartment <compartment>
Allow dynamic-group dg-oic-devops to manage compute-containers in compartment <compartment>
Allow dynamic-group dg-oic-devops to use vnics in compartment <compartment>
Allow dynamic-group dg-oic-devops to use subnets in compartment <compartment>
Allow dynamic-group dg-oic-devops to use dhcp-options in compartment <compartment>
Allow dynamic-group dg-oic-devops to use network-security-groups in compartment <compartment>
```

> Ajuste o dynamic group e o compartment conforme o padrão IAM do ambiente. Em ambientes com recursos em compartments diferentes, separe as policies por compartment.

### 8. Conectando a Build Pipeline com a Deployment Pipeline

Depois que a Deployment Pipeline estiver pronta, voltar para a Build Pipeline e adicionar o stage que dispara o deploy.

Ir na Build Pipeline -> `Add Stage` -> `Trigger Deployment`.

![trigger](images/18_trigger_deployment.png "trigger")

Preencher:

- `Stage name`: `deployOIC`;
- `Deployment Pipeline`: selecionar a pipeline criada no passo 4;
- `Send build pipelines Parameters`: selecionado.

![pipeline add stage](images/19_pipeline_build_and_deploy.png "pipeline add stage")

> O `Send build pipelines Parameters` é obrigatório para este fluxo, pois a build exporta `ARTIFACT_PATH` e `ARTIFACT_VERSION` e a deployment pipeline usa esses valores para baixar exatamente o artifact produzido naquela execução.

A ordem final da Build Pipeline deve ficar:

1. `Managed Build`: executa `build_spec_oic.yaml`;
2. `Deliver Artifacts`: publica `oic-project-car` no Artifact Registry;
3. `Trigger Deployment`: chama a Deployment Pipeline e repassa os parâmetros.


![pipeline](images/20_pipeline_completo.png "pipeline")

### 9. Executando e Validando a Esteira

Para executar:

1. Ir na Build Pipeline.
2. Clicar em `Start manual run`.
3. Informar o parâmetro `CAR_FILE_NAME` com o nome do arquivo `.car` dentro da pasta `deployments`, por exemplo `LAB-DEVOPS-DEPLOY001.car`.

  ![parameter](images/31_pipeline_build_parameter.png "parameter")

4. Acompanhar o stage `Managed Build` e validar nos logs os valores de `ARTIFACT_PATH` e `ARTIFACT_VERSION`.
5. Acompanhar o stage `Deliver Artifact` e confirmar que o `.car` foi publicado no Artifact Registry.
6. Acompanhar o stage `Trigger Deployment Pipeline`.
7. Abrir a execução da Deployment Pipeline e validar o Shell stage `deployOIC`.
8. Nos logs do Shell stage, confirmar:
   - download do artifact no passo `Download CAR from Artifact Registry`;
   - token obtido no passo `Get OIC access token`;
   - resposta HTTP `200`, `201`, `202` ou `204` no passo `Import OIC project CAR`.

![pipeline execution](images/32_pipeline_build_tests.png "pipeline execution")

Para observarmos os logs do **Deploy**, devemos ir em `Latest deployment pipelines`, selecionar o deployment pipeline que criamos e ir na aba `Deployments`, e selecionar o que corresponde ao nosso teste:

![deployments](images/33_pipeline_deployments.png "deployments")

Aqui os detalhes da execução do **Deployment pipeline**:

![deployment logs](images/34_pipeline_deploy_logs.png "deployment logs")

Após a execução, podemos verificar que o projeto foi importado no ambiente de destino do OIC:

![oic](images/35_oic_project.png "oic")

![oic details](images/36_oic_details.png "oic details")


### Exemplo de exportação de uma esteira do OCI DevOps e download de arquivo binário do Artifact Registry

O OCI DevOps não possui um comando único de "export all". Na prática, você exporta:

1. a definição do projeto;
2. build pipelines e seus stages;
3. deploy pipelines e seus stages;
4. deploy artifacts, deploy environments, triggers, repositories e connections;
5. opcionalmente, o histórico recente de build runs e deployments;
6. separadamente, o conteúdo binário dos artifacts no Artifact Registry.

Para isso, criamos os scripts abaixo:

```bash
chmod +x scripts/export_oci_devops_project.sh scripts/download_oci_generic_artifact.sh
```

Serão exportadas definições dos recursos listados e, opcionalmente, registros de execuções:

```bash
scripts/export_oci_devops_project.sh \
  --project-id ocid1.devopsproject.oc1..aaaa \
  --profile DEFAULT \
  --region sa-saopaulo-1 \
  --include-runs
```

O script gera os seguintes artefatos:

```text
exports/<projeto>-<timestamp>/
  manifest.json
  meta/
    export_context.json
  project/
  build_pipelines/
  build_pipeline_stages/
  deploy_pipelines/
  deploy_stages/
  deploy_artifacts/
  deploy_environments/
  repositories/
  triggers/
  connections/
  build_runs/        # se usar --include-runs
  deployments/       # se usar --include-runs
```

Baixar um arquivo binário do OCI Artifact Registry:

```bash
scripts/download_oci_generic_artifact.sh \
  --repository-id ocid1.artifactrepository.oc1..aaaa \
  --artifact-path "<artifact_path>" \
  --artifact-version "<artifact_version>" \
  --output-file out/deploy.car
```

## Referências
- Repositório com todos os arquivos [rchafik/oicDevops](https://github.com/rchafik/oicDevops)
- [You Must Use OAuth with the Oracle Integration Developer APIs](https://docs.oracle.com/en/cloud/paas/application-integration/integrations-user/you-must-use-oauth-oracle-integration-developer-apis.html)
- [Call the Developer APIs with Client Credentials](https://docs.oracle.com/en/cloud/paas/application-integration/integrations-user/call-developer-apis-client-credentials.html)
- [Developer API for Oracle Integration to integrate applications](https://docs.oracle.com/en/cloud/paas/application-integration/rest-api/index.html)
- [Integrate Projects and Project Deployments with a GitHub Repository](https://docs.oracle.com/en/cloud/paas/application-integration/integrations-user/integrate-projects-github-repository.html)
- [CI / CD Approaches for Oracle Integration](https://blogs.oracle.com/integration/ci-cd-approaches-for-oracle-integration)
- [Oracle Cloud Infrastructure REST API Support with the OCI Signature Version 1 Security Policy](https://docs.oracle.com/en/cloud/paas/application-integration/rest-adapter/oracle-cloud-infrastructure-rest-api-support-oci-signature-version-1-security-policy.html)
- [OCI DevOps Overview](https://docs.oracle.com/en-us/iaas/Content/devops/using/devops_overview.htm)
- [Build Specification](https://docs.oracle.com/en-us/iaas/Content/devops/using/build_specs.htm)
- [Adding a Managed Build Stage](https://docs.oracle.com/en-us/iaas/Content/devops/using/add_buildstage.htm)
- [Managing Deployment Pipelines](https://docs.oracle.com/en-us/iaas/Content/devops/using/deployment_pipelines.htm)
- [Adding a Shell Stage](https://docs.oracle.com/en-us/iaas/Content/devops/using/shell_stage.htm)
- [Notifications Overview](https://docs.oracle.com/en-us/iaas/Content/Notification/home.htm)
- [Creating a Topic](https://docs.oracle.com/en-us/iaas/Content/Notification/Tasks/create-topic.htm)

## Autores
- [João Tarla](https://www.linkedin.com/in/joao-tarla/) - LAD A-Team Solution Engineer
- [Ladan Schulte Machado](https://www.linkedin.com/in/ladanschulte/) - Cloud Engineer
- [Rodrigo Chafik Choueiri](https://www.linkedin.com/in/rchafik/) - LAD A-Team Solution Engineer
