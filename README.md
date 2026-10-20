# Jenkins CI/CD Labs

A sample Spring Boot application used to learn Jenkins and build a full CI/CD flow with Docker and Kubernetes (K3s).

**Trainer:** Wahid Hamdi

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Repository Structure](#repository-structure)
- [Lab 1: Manual deployment and Jenkins freestyle jobs](#lab-1-manual-deployment-and-jenkins-freestyle-jobs)
  - [Part I: Manual Workflow (without Jenkins)](#part-i-manual-workflow-without-jenkins)
  - [Part II: Jenkins Freestyle Workflow](#part-ii-jenkins-freestyle-workflow)
  - [Challenge: Automate the Full Deployment](#challenge-automate-the-full-deployment)
- [Lab 2: Getting started with Jenkins Pipelines](#lab-2-getting-started-with-jenkins-pipelines)
- [Troubleshooting](#troubleshooting)
- [Conclusion](#conclusion)

---

## Overview

Jenkins is an open source automation server written in Java. It automates the non-human part of the software development process: continuous integration, and the technical aspects of continuous delivery. It runs as a service or inside servlet containers such as Apache Tomcat.

| Lab | Goal | Jenkins job type |
|---|---|---|
| Lab 1 | Deploy the app manually, learn Jenkins basics, then automate the whole flow with a shell script | Freestyle |
| Lab 2 | Describe the CI/CD flow as code in a `Jenkinsfile` (clone, Maven build, Docker image, run container) | Pipeline (script from SCM) |

```
Git repo -> Maven build -> Docker image -> Docker Hub -> Kubernetes (K3s)
   \______________________ Jenkins automates all of this ______________________/
```

## Prerequisites

- Ubuntu Server VM (4 GB+ RAM, 50 GB+ disk) with the following installed:
  - Java: a **JDK** (17 or 21, not only a JRE) and Maven
  - Docker
  - Kubernetes (K3s single node) and `kubectl`
  - Jenkins (installed as a service, reachable on `http://HOST-IP:8080`)
- A Docker Hub account
- A GitHub account (fork of https://github.com/wahid007/Jenkins-Demo.git)

Quick check:

```bash
java -version
javac -version          # must exist: a JDK is needed to compile the app
mvn -version
docker --version
kubectl get nodes
systemctl status jenkins
```

## Repository Structure

| File | Purpose |
|---|---|
| `Dockerfile` | Builds the application image |
| `deployment.yaml` | Kubernetes Deployment (2 replicas) |
| `service.yaml` | Kubernetes Service (NodePort) |
| `k8s.yml` | Combined Kubernetes manifest provided with the repo |
| `Jenkinsfile` | Pipeline definition used in Lab 2 |
| `Test.java` | Simple Java file used in the freestyle lab |
| `pom.xml`, `src/` | Spring Boot application source |
| `buildspec.yml` | AWS CodeBuild file (not used in these labs) |

---

# Lab 1: Manual deployment and Jenkins freestyle jobs

## Part I: Manual Workflow (without Jenkins)

Deploy the Spring Boot application to Kubernetes by hand.

### Step 1: Dockerfile

```dockerfile
# java jdk 17
FROM eclipse-temurin:17-jre

# Set port number
EXPOSE 2222

# Set the working directory in the container
WORKDIR /app

# Copy the packaged JAR file into the container
COPY target/devOpsDemo-0.0.1-SNAPSHOT.jar app.jar

# Specify the command to run on container startup
CMD ["java", "-jar", "app.jar"]
```

> The JAR name must match the file produced by Maven (`ls target/*.jar`), and the port must match the `server.port` of the application (`grep -r "server.port" src/main/resources/`).

### Step 2: Build the project and the image

```bash
mvn clean install
docker build -t myapp:1.0.0 .
```

### Step 3: Push the image to Docker Hub

```bash
docker login -u DOCKER_HUB_USER_NAME
docker tag myapp:1.0.0 DOCKER_HUB_USER_NAME/myapp:1.0.0
docker push DOCKER_HUB_USER_NAME/myapp:1.0.0
```

Optionally test the image in a local container:

```bash
docker run --detach --name myContainerName --publish 2222:2222 DOCKER_HUB_USER_NAME/myapp:1.0.0
curl http://localhost:2222
docker rm -f myContainerName
```

### Step 4: Deploy to K3s with kubectl

**`deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: spring-app
  template:
    metadata:
      labels:
        app: spring-app
    spec:
      containers:
        - name: spring-app-container
          image: DOCKER_HUB_USER_NAME/myapp:1.0.0   # change to your image
          ports:
            - containerPort: 2222                   # the port your app listens on
```

**`service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: spring-app-service
spec:
  selector:
    app: spring-app
  ports:
    - protocol: TCP
      port: 2222          # the port your app listens on
      targetPort: 2222    # the port your app listens on
  type: NodePort
```

Apply and verify:

```bash
kubectl apply -f deployment.yaml
kubectl get pods                 # wait until STATUS is Running
kubectl apply -f service.yaml
kubectl get svc
```

### Step 5: Test the application

```bash
NODE_PORT=$(kubectl get svc spring-app-service -o jsonpath='{.spec.ports[0].nodePort}')
curl http://localhost:$NODE_PORT
```

To test the pod directly, bypassing the Service:

```bash
kubectl port-forward deployment/spring-app-deployment 2222:2222
curl http://localhost:2222
```

---

## Part II: Jenkins Freestyle Workflow

Open Jenkins at `http://SERVER_IP:8080`, then **New Item > Freestyle project**.

### Step 1: First job

1. Create a freestyle item named `freestyle_demo`.
2. Add an **Execute shell** build step:
   ```bash
   echo 'Bonjour'
   ls -l
   echo 'Bonjour DevOps' > test.txt
   ls -l
   ```
3. Run the job (**Build Now**).
4. Check that `test.txt` exists in `/var/lib/jenkins/workspace/freestyle_demo`.

### Step 2: Run a Java file

1. Create `Test.java` in `/var/lib/jenkins/workspace/freestyle_demo` that displays **Hi Master DevOps**:
   ```java
   public class Test {
       public static void main(String[] args) {
           System.out.println("Hi Master DevOps");
       }
   }
   ```
2. Add `java Test.java` to the Execute shell of the job.
3. Run the job and check the Console Output.

### Step 3: Get the script from GitHub

1. Create a repository in your GitHub account and push your script (and `Test.java`) to it.
2. In the job, go to **Configure > Source Code Management > Git** and set the repository URL and branch.
3. Update the Execute shell to run the script from the repository, for example `sh script.sh`.
4. Run the job.

### Step 4: Scheduling and build retention

1. **Build Triggers > Build periodically**: `H/5 * * * *` (every 5 minutes).
2. **General > Discard old builds**: keep only the last **2** builds.
3. **Build Environment > Delete workspace before build starts** (requires the Workspace Cleanup plugin).

---

## Challenge: Automate the Full Deployment

Create a freestyle job with a shell build that automates all steps, from the Maven build to the Kubernetes deployment.

### One-time server preparation

```bash
# Let Jenkins use Docker
sudo usermod -aG docker jenkins

# Let Jenkins use kubectl (K3s kubeconfig)
sudo mkdir -p /var/lib/jenkins/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /var/lib/jenkins/.kube/config
sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube
sudo chmod 600 /var/lib/jenkins/.kube/config

sudo systemctl restart jenkins

# Verify
sudo -u jenkins docker ps
sudo -u jenkins kubectl get nodes
```

Store your Docker Hub credentials in **Manage Jenkins > Credentials** (kind *Username with password*, ID `dockerhub-creds`), then bind them **in the job you actually run** under **Build Environment > Use secret text(s) or file(s) > Username and password (separated)** with the variables `DOCKER_USER` and `DOCKER_PASS`.

### Job: `springboot-k8s-deploy`

- **Source Code Management:** Git, your fork of this repository.
- **Execute shell:**

```bash
#!/bin/bash
set -e

IMAGE_NAME=myapp
IMAGE_TAG=${BUILD_NUMBER}
REPO=$DOCKER_USER/$IMAGE_NAME

echo "=== 1. Maven build ==="
mvn clean install -DskipTests

echo "=== 2. Docker build ==="
docker build -t $REPO:$IMAGE_TAG .

echo "=== 3. Push to Docker Hub ==="
echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
docker push $REPO:$IMAGE_TAG
docker logout

echo "=== 4. Deploy to Kubernetes ==="
sed -i "s|image:.*|image: $REPO:$IMAGE_TAG|" deployment.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

echo "=== 5. Wait for rollout ==="
kubectl rollout status deployment/spring-app-deployment --timeout=120s
kubectl get pods
kubectl get svc spring-app-service
```

Run the job, then verify:

```bash
kubectl get pods
curl http://localhost:$(kubectl get svc spring-app-service -o jsonpath='{.spec.ports[0].nodePort}')
```

---

# Lab 2: Getting started with Jenkins Pipelines

In this lab the CI/CD flow is described as code in a `Jenkinsfile` stored in the repository. The pipeline will:

1. Clone the project from GitHub
2. Build it with Maven
3. Build a Docker image
4. Run the image as a container (`localhost:2222`)

Then, as an extension, push the image to Docker Hub and deploy it to K3s.

## 1. Install and open Jenkins

Jenkins needs Java to run (Java 17 or 21):

```bash
sudo apt update
sudo apt install -y fontconfig openjdk-21-jdk maven
```

> The handout installs `openjdk-21-jre`. A JRE cannot compile the application, so install the **JDK**.

Install Jenkins as a service by following https://www.jenkins.io/doc/book/installing/linux/ (Debian/Ubuntu section), then open `http://HOST-IP:8080`.

First start:

1. Read the unlock password: `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`
2. Choose **Install suggested plugins**.
3. Create the admin user (or continue as admin).
4. Confirm the Jenkins URL, then **Save and Finish**.

## 2. Prepare the project

1. On GitHub, **fork** https://github.com/wahid007/Jenkins-Demo into your account.
2. Clone your fork on the VM and review the files:
   ```bash
   git clone https://github.com/YOUR_USER/Jenkins-Demo.git
   cd Jenkins-Demo
   cat Dockerfile Jenkinsfile
   grep -r "server.port" src/main/resources/
   ```
3. Optional: change the text of the HTML page under `src/main/resources/` to see your change deployed, then commit and push.

The application is a simple Spring Boot app that displays an HTML page with one paragraph.

## 3. Configure Jenkins

### 3.1 Plugins

**Manage Jenkins > Plugins > Available plugins**. Install:

- **Docker** and **Docker Pipeline**
- **Kubernetes CLI** (used in the extension)
- **Maven Integration** (optional for this lab, since the pipeline calls Maven directly)

Tick **Restart Jenkins when installation is complete and no jobs are running**.

### 3.2 Tools

**Manage Jenkins > Tools**:

- **Maven**: name `maven-3.9`, tick *Install automatically*, *Install from Apache*, choose the latest 3.9.x version.
- **JDK**: the handout uses the Oracle installer (needs an Oracle account). On Linux, instead add a JDK with the name `JDK` and set `JAVA_HOME` to the installed path (for example `/usr/lib/jvm/java-21-openjdk-amd64`).
- **Docker**: the handout adds an automatic installer named `MyDocker`. Docker is already installed on the VM, so this is not needed here.

> The name given to a tool is the name the `Jenkinsfile` must use in `tool '...'`. They must match exactly.

### 3.3 Docker access for Jenkins

The handout configures a Docker cloud on `tcp://IP:2375`. That is only needed for dynamic Docker agents, and port 2375 is an unauthenticated, insecure API. Since Jenkins runs on the same VM as Docker, skip it and give the `jenkins` user access to the Docker socket:

```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
sudo -u jenkins docker ps
```

## 4. Create the pipeline

1. **Dashboard > New Item**, name `Jenkins_test`, choose **Pipeline**, click OK.
2. **General**: tick **GitHub project** and enter your fork URL (`https://github.com/YOUR_USER/Jenkins-Demo`).
3. **Pipeline > Definition**: **Pipeline script from SCM**.
   - SCM: **Git**
   - Repository URL: `https://github.com/YOUR_USER/Jenkins-Demo.git`
   - Branch: `*/main`
   - Script Path: `Jenkinsfile`
4. **Save**.

## 5. The Jenkinsfile

```groovy
node {
    def mvnHome = tool 'maven-3.9'
    def dockerImageTag = "devopsexample:${env.BUILD_NUMBER}"

    stage('Clone Repo') {
        git branch: 'main', url: 'https://github.com/YOUR_USER/Jenkins-Demo.git'
    }

    stage('Build Project') {
        sh "${mvnHome}/bin/mvn clean package"
    }

    stage('Build Docker Image') {
        sh "docker build -t ${dockerImageTag} ."
    }

    stage('Deploy Docker Image') {
        echo "Docker Image Tag Name: ${dockerImageTag}"
        sh 'docker rm -f devopsexample || true'
        sh "docker run --name devopsexample -d -p 2222:2222 ${dockerImageTag}"
    }
}
```

What each part does:

- `tool 'maven-3.9'` links the variable to the Maven configured in *Manage Jenkins > Tools*.
- The four **stages** run in order: clone, Maven build, Docker image, container.
- `docker rm -f devopsexample || true` removes the container from a previous run. Without it, the second build fails because the name `devopsexample` is already used.

### Corrections to the handout's Jenkinsfile

| In the handout | Problem | Fix |
|---|---|---|
| `git "branch: 'main', url: '...'` with curly quotes | Invalid Groovy syntax | `git branch: 'main', url: '...'` |
| `sh "mvn clean package"` | `mvnHome` is defined but never used | Call `"${mvnHome}/bin/mvn ..."` or put Maven on the PATH |
| `sh "docker run ... ${dockerImageTag}` | Missing closing quote | Close the string |
| Dockerfile `COPY ...jar /app` with `CMD ["java","-jar","/app.jar"]` | The JAR is copied to `/app` but started as `/app.jar` | Use `COPY ...jar /app.jar` (the repo's Dockerfile is already correct) |
| "Initialize Docker" stage with `tool 'MyDocker'` | Not needed when Docker is installed on the host | Remove it |
| Text mentions `-H` for the Docker host | Not in the code | Not needed with the local Docker socket |

## 6. Run and verify

1. Open `Jenkins_test` and click **Build Now**.
2. Open the build and follow **Console Output**. The **Stage View** shows Clone Repo, Build Project, Build Docker Image and Deploy Docker Image in green.
3. Check the container and the page:
   ```bash
   docker ps
   docker logs devopsexample
   curl http://localhost:2222
   ```
   In a browser, open `http://VM_IP:2222`. You should see the HTML page of the application.

## 7. Extension: push to Docker Hub and deploy to K3s

This reuses the credentials and the kubeconfig from the Lab 1 challenge. Replace the contents of the `Jenkinsfile` and commit it:

```groovy
pipeline {
    agent any
    tools { maven 'maven-3.9' }
    environment {
        IMAGE = 'DOCKER_HUB_USER_NAME/devopsexample'
        TAG   = "${env.BUILD_NUMBER}"
    }
    stages {
        stage('Clone Repo') {
            steps { checkout scm }
        }
        stage('Build Project') {
            steps { sh 'mvn clean package' }
        }
        stage('Build Docker Image') {
            steps { sh 'docker build -t $IMAGE:$TAG .' }
        }
        stage('Push to Docker Hub') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                  usernameVariable: 'DOCKER_USER',
                                                  passwordVariable: 'DOCKER_PASS')]) {
                    sh '''
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        docker push $IMAGE:$TAG
                        docker logout
                    '''
                }
            }
        }
        stage('Deploy to K3s') {
            steps {
                sh '''
                    sed -i "s|image:.*|image: $IMAGE:$TAG|" deployment.yaml
                    kubectl apply -f deployment.yaml
                    kubectl apply -f service.yaml
                    kubectl rollout status deployment/spring-app-deployment --timeout=120s
                '''
            }
        }
    }
}
```

Credentials are passed with `withCredentials` inside the pipeline, so there is no per-job binding to forget. Secrets are used in single-quoted `sh` blocks so that Groovy does not interpolate them into the log.

---

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `permission denied` on `/var/run/docker.sock` | Jenkins is not in the `docker` group: `sudo usermod -aG docker jenkins`, then restart Jenkins |
| `kubectl: connection refused` or `no configuration` | Check `/var/lib/jenkins/.kube/config` |
| `ImagePullBackOff` | Wrong image name or tag, image not pushed, or private repository: `kubectl describe pod POD_NAME` |
| `CrashLoopBackOff` | The application fails at startup: `kubectl logs POD_NAME` |
| `curl: Connection refused` on the NodePort | Ports in the YAML files do not match the app's `server.port`, or pods are not ready: `kubectl get endpoints spring-app-service` |
| `java: command not found` in Jenkins | Install a JDK on the server and restart Jenkins |
| `Test.java` not found in the job | The workspace is created on the first build; copy the file there or fetch it from Git |
| `invalid tag "/myapp:12"` | `DOCKER_USER` is empty. The credentials are not bound to the job that is running (check the job name in the console output) |
| `No tool named maven-3.9 found` | The name in the `Jenkinsfile` differs from the one in *Manage Jenkins > Tools* |
| `release version 17 not supported` or `No compiler is provided` | Jenkins/Maven uses a JRE or an older JDK. Install a JDK and set `JAVA_HOME` |
| `docker: Conflict. The container name "/devopsexample" is already in use` | Add `docker rm -f devopsexample \|\| true` before `docker run` |
| `port is already allocated` on 2222 | Another container uses the port: `docker ps`, then `docker rm -f NAME` |
| Page not reachable on `VM_IP:2222` | Check `server.port` of the app, `sudo ufw allow 2222/tcp`, and `docker logs devopsexample` |

## Conclusion

These labs form a proof of concept covering the development, containerization and deployment of a Spring Boot application using Docker and K3s: first manually, then automated with a Jenkins freestyle job, and finally described as code in a Jenkins pipeline.
