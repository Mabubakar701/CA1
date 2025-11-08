# CA1 — Project Summary and Day‑One → Current Analysis

This README explains the work done from day one on this repository, the current architecture, key files and decisions, how to reproduce the environment.

## Quick summary

- create git hub account an make public repository.
- Terraform provisions an Azure VM + networking and outputs the public IP.
having main.tf, version.tf and output.tf
cd terraform
terraform init
terraform plan
terraform apply

- Ansible configures the VM (installs Docker) and deploys a Docker image that serves a static `index.html` from `app/`.
need to install WSL and ubunto
Ansible playbook code is shared which make sure the deployment of new conatiner also start and enable it
remove any existing conatiner.
add azure to docker group
check status of running container

- GitHub Actions pulls and pushes a Docker image (from `app/`) and triggers an Ansible deployment to the VM.
ansible-playbook -i /tmp/inventory.ini ansible/main.yml \
docker push ${{ secrets.DOCKER_USERNAME }}/webapp:latest

- The project previously encountered issues including: a large Terraform provider binary accidentally committed, CI Docker build context errors, Ansible `copy` recursion parameter issues, Docker port 80 conflicts on the VM.
- install docker desktop
- make account on docker hub
## Chronological analysis 
1. Day 1 — Project scaffold
   - Added `app/` with a minimal `Dockerfile` (based on `nginx`) and `index.html` as the web app.
   - Added Terraform config under `terraform/` to create a resource group, VNet, subnet, NSG (SSH/HTTP), public IP, NIC, and a Linux VM (`azurerm_linux_virtual_machine`).
   - Added Ansible playbook in `ansible/main.yml` and an inventory at `ansible/inventory.ini` to target the VM.
   - Added a GitHub Actions workflow skeleton to build/push the Docker image and deploy it.

2. Early problems and fixes
   - Git push failed due to a large provider binary in `terraform/.terraform/...terraform-provider-azurerm_v3.117.1_x5.exe`. A `.gitignore` entry was added to ignore `terraform/.terraform/` and related state/backup files.
   - CI docker build initially failed with `open Dockerfile: no such file or directory` because the build context was the repo root while the Dockerfile is under `app/`. The workflow was updated to `cd app` and `docker build -t <user>/webapp:latest .`.

3. Ansible and runtime issues
   - The playbook originally used `copy` with `recurse: yes`, which was unsupported in the target environment, producing an "Unsupported parameters" error. This was addressed by switching to `synchronize`/`rsync` or using `unarchive` in later edits.
   - Deploys sometimes failed because port 80 was already in use on the VM (Bind for 0.0.0.0:80 failed). Mitigations added: pre-deploy tasks to detect and stop containers or services that bind port 80, and fallbacks to abort with diagnostic output if the port remains occupied.
   - Shell commands that used Docker format tokens like `{{.ID}}` conflicted with Jinja templating. The solution was to wrap those shell blocks in raw tags to prevent Ansible from interpreting them.

4. CI orchestration attempts
   - Multiple workflow variants were tried: (A) CI builds and pushes image, then SSH action runs `docker pull` and `docker run` on the VM; (B) CI runs Terraform to provision/update VM, updates inventory, then runs Ansible from the runner to deploy.
   - The chosen standard flow that is recommended: CI builds & pushes the image, CI runs Terraform (with `TF_VAR_admin_public_key` if needed) to create/update VM, then CI runs Ansible using the runner's SSH key to connect and deploy.

## Key files and their responsibilities
- `app/Dockerfile` — builds the nginx-based container that serves `index.html`.
- `terraform/main.tf` — Azure resource definitions; VM uses `admin_ssh_key` referencing a public key on the runner (or via `TF_VAR_admin_public_key`).
- `ansible/main.yml` — Installs Docker, pulls the image, and runs the container. Contains tasks for stopping previous container and freeing port 80 when necessary.
- `ansible/inventory.ini` — Host inventory for the VM (example IP shown).
- `.github/workflows/deploy.yml` — CI pipeline: checkout → login to Docker → build & push image → set up SSH key → run Ansible on the VM.
- `.gitignore` — Added entries to avoid tracking Terraform's `.terraform` directory and state files.

## How to reproduce the full flow locally (recommended)
Prerequisites:
- Install Terraform, Ansible (if running locally), Docker (for local build), and Azure CLI (if provisioning from your machine).
- Ensure you have an SSH keypair at `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`.

Steps (local test):

1. Build the Docker image locally and test it:

```powershell
cd app
docker build -t myuser/webapp:latest .
docker run -d -p 8080:80 myuser/webapp:latest
# Visit http://localhost:8080 to confirm the app is served
```

2. Provision Azure resources locally (manual terraform run):

```powershell
cd terraform
$env:TF_VAR_admin_public_key = Get-Content $HOME\.ssh\id_rsa.pub -Raw
terraform init
terraform apply -auto-approve
terraform output public_ip_address
```

3. Update `ansible/inventory.ini` with the VM public IP and run Ansible from your machine:

```powershell
# edit ansible/inventory.ini to set the public IP
ansible-playbook -i ansible/inventory.ini ansible/main.yml -e "docker_image=myuser/webapp docker_tag=latest"
```

4. Or run the CI flow (on GitHub): push to `main` with the following repository secrets set:
- `DOCKER_USERNAME`, `DOCKER_PASSWORD` (Docker Hub credentials)
- `VM_SSH_KEY` (private key) and `VM_HOST` (public IP or DNS)
- Optional: `AZURE_CREDENTIALS` (sdk-auth JSON) if you want Actions to run Terraform using azure/login

CI will build & push the container image and then run Ansible to deploy.

## Troubleshooting tips (collected during development)
- If `git push` fails due to large files, run:

```powershell
git rm -r --cached terraform/.terraform
git commit -m "Remove tracked terraform plugins"
git push
```

- If GitHub Actions fails during the Docker build with a missing Dockerfile, ensure the build step runs from `app` or use `docker build -f app/Dockerfile ./app`.

- If `ansible` reports `Unsupported parameters: recurse` for `copy`, replace with `synchronize` or `unarchive`.

- If `docker run` fails with `port is already allocated`, inspect the VM for processes binding port 80:

```powershell
ssh azureuser@<VM_IP>
# then on VM
ss -ltnp | grep :80
docker ps --filter "publish=80" --format "{{.ID}}: {{.Names}} {{.Ports}}"
```

