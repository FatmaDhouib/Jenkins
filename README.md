# Jenkins CI/CD Pipeline Lab

A sample Spring Boot application used to learn Jenkins and build a full CI/CD flow with Docker and Kubernetes (K3s).

**Trainer:** Wahid Hamdi

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Repository Structure](#repository-structure)
- [Part I: Manual Workflow (without Jenkins)](#part-i-manual-workflow-without-jenkins)
- [Part II: Jenkins Freestyle Workflow](#part-ii-jenkins-freestyle-workflow)
- [Challenge: Automate the Full Deployment](#challenge-automate-the-full-deployment)
- [Troubleshooting](#troubleshooting)
- [Conclusion](#conclusion)

---

## Overview

Jenkins is an open source automation server written in Java. It automates the non-human part of the software development process: continuous integration, and the technical aspects of continuous delivery. It runs in servlet containers such as Apache Tomcat.

In these labs you will:

1. Build, containerize and deploy a Spring Boot application manually.
2. Learn Jenkins through freestyle jobs.
3. Automate the whole flow (Maven build, Docker image, Docker Hub push, Kubernetes deployment) in one Jenkins job.

```
Git repo -> Maven build -> Docker image -> Docker Hub -> Kubernetes (K3s)
   \______________________ Jenkins automates all of this ______________________/
```

## Prerequisites

- Ubuntu Server VM with the following installed:
  - Java JDK 17 and Maven
  - Docker
  - Kubernetes (K3s single node) and `kubectl`
  - Jenkins
- A Docker Hub account
- A GitHub account
- This repository: https://github.com/wahid007/Jenkins-Demo.git

Quick check:

```bash
java -version
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
| `Jenkinsfile` | Pipeline definition (pipeline-style job) |
| `Test.java` | Simple Java file used in the freestyle lab |
| `pom.xml`, `src/` | Spring Boot application source |
| `buildspec.yml` | AWS CodeBuild file (not used in these labs) |

---

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

sudo systemctl restart jenkins
```

Store your Docker Hub credentials in **Manage Jenkins > Credentials** (kind *Username with password*, ID `dockerhub-creds`), then bind them in the job under **Build Environment > Use secret text(s) or file(s)** as `DOCKER_USER` and `DOCKER_PASS`.

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

## Conclusion

These labs form a proof of concept covering the development, containerization and deployment of a Spring Boot application using Docker and K3s, first manually and then automated with Jenkins.
