# Setup

## Prerequisites

* Docker
* AWS CLI
* An AWS account with administrative privileges.

### Docker image

There's a `Dockerfile` containing all the tools that are used in the project. You can either:

* Build the image and use it locally: `docker build -t cloud-tools .` 
* Use the already-available image `afakharany/cloud-tools`

### DC procedure

The following steps will deploy the infrastructure and the application on the DC (data center) site.

#### 1. Create the Terraform state bucket

We use an S3 bucket to store Terraform state. This bucket needs to be created before proceeding.

```bash
docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt  afakharany/cloud-tools /opt/infrastructure/scripts/init.sh your.bucket.name
```

##### Note about AWS profile

The above command assumes that you are using the `default` AWS profile. If you need to use a different one, you must pass `AWS_PROFILE` in the command. For example:

```bash
docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt -e AWS_PROFILE=dev  afakharany/cloud-tools /opt/infrastructure/scripts/init.sh your.bucket.name
```

**This applies to all subsequent commands that make use of AWS (for example, Terraform). For the rest of the document, we assume that the profile in use is `default`**

#### 2. Initialize Terraform

Configure your backend in `infrastructure/dc/main.tf` as follows:

```bash
vim infrastructure/dc/main.tf
```

Modify lines 6 to 9 as follows:

```plain
  backend "s3" {
    bucket = "your.bucket.name"
    key    = "default.tfstate"
    region = "your-region"
  }
```

Save the file. Initialize Terraform by running the following command:

```bash
docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/dc init
```

#### 3. Configure your values

Before deploying the infrastructure, we need to revise and configure the values that will be applied. Infrastructure values are stored in `infrastructure/dc/main.tf` file under the `locals` stanza. The followig is a list of the availabe values and what that do:

* `cluster_name`: The name that the EKS cluster will use.
* `cluster_version`: The Kubernetes version that will be used.
* `instance_type`: The EC2 instance type for the worker nodes. We recommend it's a `t3.medium` or higher.
* `vac_name`: The name of the VPC that will host the infrastructure.
* `min_nodes`: The minimum number of worker nodes that the cluster will have at any time.
* `max_nodes`: The maximum number of worker nodes that the cluster will have at any time.
* `desired_nodes`: The desired number of worker nodes. By default, it's set to the same value as `min_nodes`
* `region`: The region where the infrastructure will be hosted.
* `k8s_service_account_namespace`: The namespace that will hold the Kubernetes service account responsible for handling cluster autoscaling. We highly recommend setting it to `kube-system`.
* `k8s_service_account_name`: The Kubernetes service account that is used by the cluster autoscaler component.
* `vpc_cidr_block`: The CIDR block that the VPC will use. We recommend setting it to a different value than DR (see below) so that VPC peering can be enabled later on if requierd.
* `pod-s3-subjects`: The service account names and namespaces that will be used to access S3 buckets. Any pod in the said namespace that uses the said service account will be granted access to the assets S3 bucket. For example, `["system:serviceaccount:default:pods3", "system:serviceaccount:dev:pods3"]` grants the assets bucket access to any pod in the `default` and `dev` namespaces provided that it uses the `pods3` service account.
* `domain`: The domain that will host the application and its helper components. **This domain should be manually created on Route 53 before proceeding**. The reason I didn't automate its creation is that I use a different domain registrar for `fakharany.com` than Route 53 (GoDaddy). I needed to delegate `dev.fakharany.com` to Route 53 by copying the NS records from the zone to GoDaddy DNS. 
* `zoneid`: The zone ID of the `domain`.
* `assets-bucket`: The S3 bucket that would hold Ghost assets.
* `externalDNS-enabled`: Wehther to enable the externalDNS component. Enabled by default on DC. (see DC to DR switch below)

#### Note about Ghost integration with S3

It was mentioned in the [documentation](https://ghost.org/integrations/amazon-s3/) that Ghost can integration with S3 buckets to store static assets (images) using a component called [ghost-storage-adapter-s3](https://github.com/colinmeinke/ghost-storage-adapter-s3). However, the component **does not** support using AWS SSO for authentication, which EKS uses to grant IAM access to pods. In the experiments, I verified that the pod was able to access and work with the designated S3 bucket through `aws sts` command and assuming the role assigned to the pod. Unfortunately, Ghost and the integrator do not support that as of the time of this writing. Please see below for possible work arounds.

#### 4. Building the infrastructure 

Deploy the needed infrastructure components by running the following:

```bash
docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/dc plan
docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/dc apply -auto-approve
```

The above commands will create the following:

* A VPC with the followig:
  * Two private subnets for Kubernetes worker nodes
  * Two public subnets for the load balancers to work
  * A DB subnets (if we need to deploy RDS)
  * The subnets use the first two available availablity zones in the selected region
  * The required internet gateway, NAT gateway, public/private routes, and route bindings.
* An EKS cluster which automatically creates the following:
  * Autosacling group that spans the private subnets
* The Kubernetes cluster autoscaler (used to autoscaling nodes based on load)
* The AWS Load Balancer Controller (used to enable and manage Kubernetes Ingress that used the AWS application load balancer)
* The ExternalDNS component (used to automatically update Route53 records when a new Ingress is created or updated).

#### 5. Accessing the cluster

Please take note of the output produced by Terraform. For exameple:

```bash
Outputs:

acm_certificate_arn = "arn:aws:acm:eu-west-1:youraccount:certificate/613e60d7-a205-4cf9-ae41-129b82011818"
pods3_role_arn = "arn:aws:iam::youraccount:role/eu-west-1-pods3"
```

We need those values when deployign the application and its components.

At any time you can get them back by running:

```bash
docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/dc refresh
```

Once Terraform finished, you should find the KUBECONFIG file under `infrastructure/dc/kubeconfig_cluster_name` where `cluster_name` is the name you selected for the cluster.

You can verify that the cluster is healthy by using a utility look `k9s`. For example:

```bash
docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt -e KUBECONFIG=/opt/infrastructure/dc/kubeconfig_ghost afakharany/cloud-tools k9s
```

#### 6. Deploying the database

Ghost supports MySQL as the backend database. We can install the `bitnami/mariadb` Helm chart using a command like the following:

```bash
docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt -v $(pwd)/infrastructure/dc/kubeconfig_ghost:/root/.kube/config afakharany/cloud-tools helm upgrade --install mariadb01 --set auth.rootPassword=foo,auth.database=bar,auth.username=ghostuser,auth.password=foo bitnami/mariadb
```

#### 7. Deploying Ghost

Ghost is deployable through a Helm chart that lives in `helm/ghost`. The required parameters are saved in `helm/ghost/values.yaml` . You need to change the following values:

* `serviceAccount.annotations.eks.amazonaws.com/role-arn`: The `pods3_role_arn` from the Terraform command output.

* `ingress.annotations.service.beta.kubernetes.io/aws-load-balancer-ssl-cert`: The SSL certificate ARN from the Terraform output.

* `ingress.annotations.external-dns.alpha.kubernetes.io/hostname`: The application domain (for example, www.example.com)

* `ingress.hosts.host`: The application domain (for example, www.example.com)

* `resources`: Configures the CPU and memory requests and limits. The default values were found optimal for Ghost but they can be adapter later for different workloads. 

* `autoscaling`: Defines how the HPA (Horizontal Pod Autoscaler) scales pods in and out. The values are optimized for Ghost but they can always be changed depending on the workloads.

* `appUrl`: The application URL. For example, "https://www.example.com"

* Run the following command to deploy Ghost:

  ```bash
  docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt -v $(pwd)/infrastructure/dc/kubeconfig_ghost:/root/.kube/config afakharany/cloud-tools helm upgrade --install ghost01 --set dbHost=mariadb01,appUsername=ghostuser,appPassword=bar,dbName=ghostdb ./helm/ghost
  ```

  Make sure you use the appropriate values as defined when deploying the database.

* In a few minutes, you can navigate to the URL of the application and access it. You can use `http://` or `https://` as the request will automatically be redirected to `https://`.

#### 8. Using the delete Lambda function

* The project deploys a serverless function called `delete-lambda`. It is used to delete all the posts in Ghost. To use it, you need to acquire an admin API key and  URL. 
* Login to Ghost by navigating to `/ghost` and creating an account.
* Go to "integrations" and create a custom integration. You can give it any name. Copy the API key.
* In the Lambda function supply the API and URL environment variables with the application URL and the API key.
* Run the function to delete all the posts.

#### 9. Creating namespaces and users

* Using namespaces, we can grant different devs or DevOps teams access to a specific application deployment.

* For example:

  ```bash
  docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt -v $(pwd)/infrastructure/dc/kubeconfig_ghost:/root/.kube/config afakharany/cloud-tools kubectl create ns dev
  ```

* The project is configured to create two profiles: `dev` and `sec`. The first one is for developers. For demo purposes, users in this profile have full access to the `dev` namespace. The `sec` profile users have read-only access to all namespaces.

* The following commands create the necessary AWS IAM users and groups with two users: `john` in the `dev` group and `jane` in the `sec` one:

  ```bash
  docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/users init
  docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/users plan
  docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/users apply -auto-approve
  ```

* Apply the rbac role in the `users` directory:

  ```bash
  docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt -v $(pwd)/infrastructure/dc/kubeconfig_ghost:/root/.kube/config afakharany/cloud-tools kubectl apply -f /opt/infrastructure/users/dev-role.yaml -n dev
  ```

* Configure the cluster to acknowledge the `dev` role. The role arn can be retrieved from the Terraform output.

  ```bash
  docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt -v $(pwd)/infrastructure/dc/kubeconfig_ghost:/root/.kube/config afakharany/cloud-tools eksctl create iamidentitymapping --cluster ghost --arn arn:aws:iam::youraccount:role/dev-role --username john
  ```

* Configure the `kubeconfig` file for `john`. You can use the same `kubeconfig_ghost` file but the `users` part should look like this:

  ```yaml
  users:
  - name: eks_ghost
    user:
      exec:
        apiVersion: client.authentication.k8s.io/v1alpha1
        command: aws-iam-authenticator
        args:
          - "token"
          - "-i"
          - "ghost"
          - "-r"
          - "arn:aws:iam::youraccount:role/dev-role"
  ```

#### 10. Testing autoscaling (Load Testing)

* It is recommended that you use `k9` while applying this procedure to see the new pods/nodes as they get added.

* Run the following command from a client:

* ```bash
  while true; do
  	curl -s https://dev.ghost.fakharany.com # Replace this with the URL
  done &
  ```

* Run the above command several times to mimic a load influx

* Notice how the new pods get added to the cluster.

* As soon as more pods get added, new ones start entering the `pending` state. 

* After some time, a new node will join the cluster to host the pending pods.

* You can use a command like `ps -ef | grep curl | awk '{print $3}' | xargs kill` to kill the `curl` commands.

* Watch the pods as they cool down gradually. 

* After some time, the new node(s) will leave the cluster since they are no longer needed.

#### 11. Deploying the monitoring stack (Prometheus and Grafana)

* Deploy Prometheus by running the following command:

  ```bash
  docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt -v $(pwd)/infrastructure/dc/kubeconfig_ghost:/root/.kube/config afakharany/cloud-tools helm upgrade --install prometheus -n kube-system  bitnami/kube-prometheus
  ```

* To deploy Grafana, you need to configure the values in `helm/grafana/values.yaml`. Specifically, the `hostname`, the `service.beta.kubernetes.io/aws-load-balancer-ssl-cert` and the `external-dns.alpha.kubernetes.io/hostname`. 

* Then, deploy using the following command:
```bash
docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt -v $(pwd)/infrastructure/dc/kubeconfig_ghost:/root/.kube/config afakharany/cloud-tools helm upgrade --install grafana -n kube-system -f helm/grafana/values.yaml bitnami/grafana
```

### DR Procedure

* Follow the steps from 1 to 10 making sure you change the region to your selected DR one. In the example, the DC region is `eu-west-1 (Ireland)` while the DR one is `eu-west-2 (London)`.

* Infrastructure: 

  ```bash
  docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/dr plan
  docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/dr apply -auto-approve
  ```

* Database:

  ```bash
  docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt -v $(pwd)/infrastructure/dr/kubeconfig_ghost-dr:/root/.kube/config afakharany/cloud-tools helm upgrade --install mariadb01 --set auth.rootPassword=foo,auth.database=ghostdb,auth.username=foo,auth.password=bar,auth.replicationPassword=foo bitnami/mariadb
  ```

* For Ghost and Grafana, make sure you have the correct role and cert ARNs from Terraform output as per the DC procedure

* Ghost:

  ```bash
  docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt -v $(pwd)/infrastructure/dr/kubeconfig_ghost:/root/.kube/config afakharany/cloud-tools helm upgrade --install ghost01 --set dbHost=mariadb01,appUsername=foo,appPassword=bar,dbName=ghostdb ./helm/ghost
  ```

* Monitoring stack:

  ```bash
  docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt -v $(pwd)/infrastructure/dr/kubeconfig_ghost-dr:/root/.kube/config afakharany/cloud-tools helm upgrade --install prometheus -n kube-system  bitnami/kube-prometheus
  docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt -v $(pwd)/infrastructure/dr/kubeconfig_ghost-dr:/root/.kube/config afakharany/cloud-tools helm upgrade --install grafana -n kube-system -f helm/grafana/values.yaml bitnami/grafana
  ```

  

## DC/DR switching and falling back

### DR as a warm site

* Deploy the infrastructure as per the DR steps. Make sure the `externalDNS-enabled` in `dr/main.tf` file is set to `false`. This will ensure that DR will not take owner ship of the DNS records. 

* In case of disaster or when you want to switch to DR, do the following:

  * Change `externalDNS-enabled` to `false` in `dc/main.tf`

  * Apply the changes:

    ```bash
    docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/dc plan
    docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/dc apply -auto-approve
    ```

  * Change `externalDNS-enabled` to `true` in `dr/main.tf`

  * Apply the changes:

    ```bash
    docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/dr plan
    docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/dr apply -auto-approve
    ```

  * In a few seconds, the Route 53 records will point to the DR site.

* To fallback to DC, reverse the steps above as follows:

  * Change `externalDNS-enabled` to `false` in `dr/main.tf`

  * Apply the changes:

    ```bash
    docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/dr plan
    docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/dr apply -auto-approve
    ```

  * Change `externalDNS-enabled` to `true` in `dc/main.tf`

  * Apply the changes:

    ```bash
    docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/dc plan
    docker run -it -v ~/.aws:/root/.aws -v $(pwd):/opt afakharany/cloud-tools terraform -chdir=infrastructure/dc apply -auto-approve
    ```

  * Having DR as a warm site will ensure that you can switch to DR in a few seconds. However, you will incure the costs of keeping an infrastructure replica on standby.

### DR as a cold site

* Deploying DR as a cold site will ensure that you reduce costs by keeping only one replica of your infrastructure in service. 
* In this procedure, you deploy DR only when needed by following the steps in "DR procedure" above. Before proceeding, make sure you set `externalDNS-enabled` to `false` in DC and apply the changes.

# Considerations that were not implemented

## DB is not in sync between DC and DR

The databases in DC and DR are not in sync by design. The following are different approaches to address this issue:

## Using MariaDB

We can still use MariaDB as the backend database. Syncing sites can be done in one of the followig ways:

### Backup and restore approach

* Deploy a Kubernetes cron job that periodically backs up the database to an S3 bucket.
* The S3 bucket should implement versioning for resilience purposes.
* DR as a cold site:
  * When the DR is brought up, a Kubernetes job downloads the latest backup file from the S3 bucket and restores it to MariaDB.
* DR as a warm site:
  * There would be a cron job that automatically grabs and restores the backup file from the bucket to the database. 
  * In this scenario, the DB acts as a read replica to DC.

### EBS Volume snapshots approach

* MariaDB stored the data on an EBS volume. We can enable AWS lifecycle on this volume to automatically create snapshots on periodic basis.
* A Lambda function can periodically copy that snapshot to the DR region and create a new EBS volume from it.
* When MariaDB starts, we configure it to use the cloned volume instead of creating a new one.
* This approach works with DR when implemented as cold or warm sites.

## DR as a hot site

* In this approach, the DR is always running. So DC and DR act as active/active.
* To implement this, we need a central DB to serve both sites at the same time. We can use AWS Aurora with multi-region support.
* Route 53 records will be imlpemented as "Weighted Records". 
* ExternalDNS will need to be disabled on both sites to avoid creating conflicting DNS records.
* Switching from DC to DR is as simple as changing the weight of the record to direct all traffic to DR or fall back to DC.
* This solution is the most resillient and fault tolerant, but it is also the most expensive.

### Ghost does not support AWS SSO to sync with the S3 bucket

* As per the documentation, Ghost does *not* support any sort of clustering. Sharding and scaling shoud be done by placing a caching layer in front of it.
* In an AWS enviornment, S3 (with CloudFront later on) is the perfect caching layer. 
* EKS uses the OICD service provider to grant pods access to AWS resources through service accounts that assume roles. This is not supported by Ghost and its S3 integrator project.
* This can be handled in one of two ways:
  * Fork the [ghost-storage-adapter-s3](https://github.com/colinmeinke/ghost-storage-adapter-s3) code and try to implement authentication through Service Token.
  * Create a sidecar container that lives in the same pod as Ghost. The sidecar container - by definition - has access to the Ghost's container filesystem. Through `inotify`, it can sync files between the container and the S3 bucket. The logic can be implemented in any programming language (I personally prefer Go).
