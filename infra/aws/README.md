# AWS deployment and access

Terraform manages two sets of resources:

- `bootstrap/`: a private, encrypted, versioned S3 state bucket, GitHub OIDC provider (or reference to an existing one), and a deployment role restricted to this repository and branch. Its initial state is stored locally, outside Git.
- `terraform/`: ECR repositories, dedicated VPC, two subnets, routing, security groups, Application Load Balancer, ECS cluster and service, task execution role, and seven-day logs. The Next.js frontend and Kotlin API share one Fargate task; port 8080 is never exposed. Optional owned-domain configuration adds ACM, certificate validation records, HTTPS, and a DNS alias.

The previous CloudFormation draft has been replaced. No CloudFormation stack or AWS resources have been created from this repository.

## 1. Sign into your existing AWS account

On your computer, install a current AWS CLI v2, Terraform 1.17.1, and GitHub CLI (`gh`). Docker is needed only if you deploy from your computer; GitHub's runner supplies it for Actions deployments.

Use an AWS IAM Identity Center session or an existing short-lived administrator profile for the one-time bootstrap. For an account with Identity Center already configured:

```sh
aws configure sso --profile admin-tool
aws sso login --profile admin-tool
export AWS_PROFILE=admin-tool
export AWS_REGION=eusc-de-east-1
aws sts get-caller-identity --region "$AWS_REGION"
gh auth login
```

During SSO configuration use your account's access portal URL, not a guessed URL, and choose the account/permission set authorized to create the resources below. If your account does not have IAM Identity Center configured, your account administrator must first enable it and assign you a permission set, or provide an existing short-lived authenticated CLI session. Do not put credentials in GitHub variables, source files, or chat. You never need to give ChatGPT your account password.

`aws.eu` uses the `aws-eusc` partition and Germany region `eusc-de-east-1`; ordinary European AWS accounts use the `aws` partition and regions such as `eu-central-1`. Select the region belonging to your actual account. The configuration derives IAM ARNs and OIDC audience from the partition, and ECR hostnames from AWS outputs. Use recent AWS CLI/SDK versions that recognize your region.

The human bootstrap identity needs permission to manage S3 state storage, IAM OIDC providers, and the deployment role and its policy. Terraform shows the plan before creating them. The generated role can manage the named ECR repositories and task execution role, its state objects, and the regional infrastructure API operations listed in `bootstrap/main.tf`. Some infrastructure operations require `Resource = "*"`; this is a deployment role with substantial write access to networking, ECS, ALB and ACM in the selected region, not a read-only role or an account administrator role.

### Alternative when browser CLI login fails and SSO is not enabled

There is no need to enable IAM Identity Center or create an AWS organization solely for this bootstrap. The organization-wide setup can change account billing/free-tier treatment. If `aws login` returns an error and you do not already have SSO, use this one-time IAM-user path from your existing administrator console session:

1. In **IAM → Policies → Create policy → JSON**, paste [bootstrap-user-policy.json](bootstrap-user-policy.json). Save it as `admin-tool-bootstrap`. This policy targets the default stack name and European Sovereign Cloud region only. It allows managing the named state bucket, GitHub identity provider, and named deployment role; it does not grant `AdministratorAccess`. It is still powerful: the bootstrap can write the deployment role's infrastructure permissions.
2. In **IAM → Users → Create user**, create `admin-tool-bootstrap`, leave console access disabled, and attach the `admin-tool-bootstrap` policy. Use **Attach policies directly** and search for the policy you just created.
3. Open that user's **Security credentials → Create access key**, select the CLI use case if prompted, and create a key. Use this IAM user's key, never a root access key.
4. On your Mac, run `aws configure --profile admin-tool-bootstrap`. Enter the key ID and secret directly in Terminal, set region to `eusc-de-east-1`, and output to `json`. The CLI stores them locally; do not paste them into chat, GitHub, or repository files.
5. Verify with `aws sts get-caller-identity --profile admin-tool-bootstrap --region eusc-de-east-1`, then run the access script below with `AWS_PROFILE=admin-tool-bootstrap`.
6. After `Access ready`, delete the access key in IAM. GitHub will use temporary OIDC credentials for app deploy/destroy. Keep the local bootstrap Terraform state private and backed up. Full `destroy.sh --all` later needs a fresh authenticated administrator/bootstrap session; the deleted key will not work.

The temporary IAM user and its policy are account-access prerequisites created manually in this alternative. They are not owned by the app Terraform stack; delete the user and policy in IAM when finished. If a GitHub OIDC provider already exists, use the existing-provider option below so the bootstrap does not attempt to create a duplicate.

## 2. Run one-time access setup

Check out the deployment branch:

```sh
git clone https://github.com/dynamitediscodaddy/admin-tool.git
cd admin-tool
git switch feature/container-deployment
./infra/aws/setup-access.sh
```

Review the plan and type `yes`. The script creates the access resources and writes **non-secret** GitHub Actions variables: `AWS_DEPLOY_ROLE_ARN`, `AWS_REGION`, `AWS_OIDC_AUDIENCE`, and `TF_STATE_BUCKET`. The `gh` session needs permission to manage repository Actions variables. If setting variables fails after Terraform succeeds, rerun the script; Terraform reconciles the existing bootstrap.

Keep `infra/aws/bootstrap/terraform.tfstate` and its backup **private and backed up**. They are ignored by Git. This local bootstrap state is needed to destroy the access resources later. Application state is stored remotely with S3 lock files and bucket versioning. Do not delete or lose the state bucket before destroying the app.

If GitHub OIDC is already registered in the AWS account, avoid creating a duplicate:

```sh
export TF_VAR_existing_oidc_provider_arn='arn:aws-eusc:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com'
./infra/aws/setup-access.sh
```

The existing provider must include the audience printed by the bootstrap (`sts.amazonaws.eu` for `aws-eusc`, `sts.amazonaws.com` for standard AWS). Terraform will not own or delete that existing provider.

The setup script queries GitHub’s OIDC settings to detect its subject prefix, including immutable owner/repository IDs on newer repositories. Direct Terraform use defaults to this repository’s immutable subject prefix; set `github_subject_prefix` for a different repository. By default the role trusts only `dynamitediscodaddy/admin-tool` on `feature/container-deployment`. Deploy workflows cannot assume it from other branches or forks. When moving deployment to main, rerun setup with `DEPLOY_BRANCH=main`, then run workflows on main. Review protection for the trusted branch; anyone who can modify and dispatch its workflow can use the deployment role.

## 3. Deploy

The workflow must be committed/pushed and access setup must have succeeded. A manual workflow must also exist on the repository's default branch for GitHub to expose `workflow_dispatch`. Merge the reviewed workflow into main before dispatching it; its run can then target the trusted deployment branch.

```sh
gh workflow run aws.yml --ref feature/container-deployment -f action=deploy
```

Or choose **Actions → AWS deployment → Run workflow**, select the trusted branch, and choose `deploy`. It bootstraps ECR only on the first run, builds both linux/amd64 images, reuses immutable images on retries, deploys the service, waits for health, and verifies the API. The AWS CLI `services-stable` waiter checks readiness using `DescribeServices`, then an HTTP API check must succeed before the URL appears in the workflow summary. Terraform creates/updates the service without its newer deployment-status API waiter; use the deployment helper for end-to-end health verification. Subsequent committed versions receive distinct image tags.

For a local deployment with the same authenticated AWS session, Docker, and a clean committed checkout:

```sh
export TF_STATE_BUCKET="$(terraform -chdir=infra/aws/bootstrap output -raw state_bucket)"
./infra/aws/deploy.sh
```

The scripts preserve native Terraform plan/approval prompts locally. GitHub's explicitly dispatched workflow uses `-auto-approve`. Do not run local apply/destroy at the same time as a workflow; S3 state locking prevents simultaneous state writes. CI never provisions cloud resources.

### HTTPS and a domain

Without a domain the demo uses the ALB's **HTTP** address and mock data only. It has no authentication. There is no CloudFront dependency or assumption about its availability in the sovereign partition.

For HTTPS, use an existing public Route 53 hosted zone in this AWS account with working DNS delegation. Set these environment variables before bootstrapping so the deployment role can update just that hosted zone:

```sh
export APP_DOMAIN_NAME=dashboard.your-domain.example
export APP_HOSTED_ZONE_ID=YOUR_EXISTING_ZONE_ID
./infra/aws/setup-access.sh
```

For GitHub deployments, also set repository variables `APP_DOMAIN_NAME` and `APP_HOSTED_ZONE_ID` to those values. For local deployments keep the environment variables set. Terraform creates the ACM certificate, DNS validation records, A alias, HTTPS listener, and HTTP-to-HTTPS redirect. It deletes those records and certificate on destroy; the existing zone and domain registration remain yours. Do not specify a hostname that already has a conflicting DNS record.

Use HTTPS and add authentication before replacing mock data with financial information. Certificate validation requires correct public delegation and can take time.

## Destroy

From GitHub, dispatch the same workflow with `action=destroy` to remove **all app resources and stored ECR images**. This leaves only the small bootstrap state bucket and deployment access so you can deploy again:

```sh
gh workflow run aws.yml --ref feature/container-deployment -f action=destroy
```

From your computer:

```sh
./infra/aws/destroy.sh        # app, registries/images, networking, logs, optional DNS/certificate
./infra/aws/destroy.sh --all  # above, then state bucket/history and owned OIDC/deployment role
```

Full cleanup requires your original human bootstrap credentials and local bootstrap state. The GitHub deployment role deliberately cannot delete itself or its state bucket. Terraform displays each destroy plan for review. The state bucket and ECR repositories allow deletion of their contents specifically for this teardown flow. After full cleanup remove the four AWS repository variables, and the optional domain variables if set. Imported/existing OIDC providers, hosted zones, account-wide AWS service-linked roles created automatically by AWS, and domain registrations are shared account resources and are not removed.

No database, NAT gateway, persistent app data volume, or manually created image repository is left outside Terraform. AWS billing records and ordinary account audit history are not application resources and remain with AWS.

## Cost and availability

The demo runs one 0.5-vCPU/1-GB task continuously, an ALB, public IPv4 addresses, ECR image storage, logs, and an S3 state bucket. It is billable even when idle; actual pricing depends on your partition, region and usage. Review the Terraform plan and your account's pricing before applying. This initial deployment has one task, no autoscaling, and no high-availability guarantee. ECS deployment circuit breakers roll back failed service updates.

## Validate without credentials

```sh
terraform fmt -check -recursive infra/aws
terraform -chdir=infra/aws/bootstrap init -backend=false
terraform -chdir=infra/aws/bootstrap validate
terraform -chdir=infra/aws/bootstrap test
terraform -chdir=infra/aws/terraform init -backend=false
terraform -chdir=infra/aws/terraform validate
terraform -chdir=infra/aws/terraform test
bash -n infra/aws/*.sh
```

Tests use mocked providers; they validate registry cleanup, repo/branch-scoped access, partition handling, network boundaries, service configuration and optional HTTPS without creating AWS resources. Actual IAM authorization, regional service availability, container startup and end-to-end deployment still need validation against your connected account.
