# CA1 — Project Summary (Day‑One → Current)

This repository contains a small end‑to‑end demo: Terraform provisions an Azure VM, Ansible configures it and deploys a Dockerized static web app, and GitHub Actions builds and pushes the Docker image.

This README summarizes the work done from day one through the present, the main files and responsibilities, how to reproduce the flow, troubleshooting notes, and recommended next steps.

## One‑line summary
- Terraform provisions networking and a Linux VM on Azure.
- Ansible installs Docker on the VM and runs a container serving `app/index.html`.
- GitHub Actions builds and pushes the Docker image from `app/` and triggers a deployment to the VM.

## Chronological summary (day one → now)
1. Project scaffolded with `app/` (static site + `Dockerfile`), `terraform/` (Azure resources), and `ansible/` (playbook + inventory).
2. CI pipeline added (`.github/workflows/deploy.yml`) to build/push Docker image and deploy to the VM via Ansible or SSH.
3. Problems encountered and fixes applied during development:
   - Large Terraform provider binary accidentally committed → added `.gitignore` entries for `terraform/.terraform/` and state files.
   - CI failed to find the Dockerfile because the build context was repo root; fixed by building from `app/`.
   - Ansible `copy` with `recurse: yes` produced "Unsupported parameters" → use `synchronize`/`unarchive` instead.
   - Docker run failed with "Bind for 0.0.0.0:80 failed" on the VM; added pre‑deploy tasks to detect and stop services/containers using port 80.
   - Jinja templating collided with Docker `--format '{{.ID}}'` → wrap shell blocks in raw tags or escape templates.

## Key files
- `app/Dockerfile` — nginx-based image that serves `index.html`.
- `terraform/main.tf` — Azure resource group, VNet, subnet, NSG, public IP, NIC, and `azurerm_linux_virtual_machine`.
- `ansible/main.yml` — Playbook to install Docker, pull/run the container (or build on VM), and manage lifecycle.
- `ansible/inventory.ini` — Example inventory pointing at the VM.
- `.github/workflows/deploy.yml` — CI workflow that builds & pushes the Docker image and runs Ansible to deploy it.
- `.gitignore` — Ignore Terraform local working dir and state files.

## How to reproduce (local quick run)
1. Build and test the container locally:

```powershell
cd app
docker build -t myuser/webapp:latest .
docker run -d -p 8080:80 myuser/webapp:latest
# Open http://localhost:8080
```

2. Provision Azure (if running Terraform locally):

```powershell
cd terraform
$env:TF_VAR_admin_public_key = Get-Content $HOME\.ssh\id_rsa.pub -Raw
terraform init
terraform apply -auto-approve
terraform output public_ip_address
```

3. Update `ansible/inventory.ini` with the VM IP and run the playbook (or let CI handle it):

```powershell
ansible-playbook -i ansible/inventory.ini ansible/main.yml -e "docker_image=myuser/webapp docker_tag=latest"
```

## Troubleshooting tips (quick)
- Remove tracked Terraform plugins if you accidentally committed them:

```powershell
git rm -r --cached terraform/.terraform
git commit -m "Remove tracked terraform plugins"
git push
```

- If GitHub Actions fails to find the Dockerfile, make sure the workflow builds from `app/`:

```yaml
# in workflow
run: |
  cd app
  docker build -t ${{ secrets.DOCKER_USERNAME }}/webapp:latest .
```

- If `docker run` fails with `port is already allocated`, check the VM for processes using port 80 and stop them before starting the new container.

## Recommended next steps
- Replace shell-based Docker management in Ansible with `community.docker` modules (`docker_image`, `docker_container`) for idempotency.
- Configure a remote Terraform backend (Azure Storage) for team-safe state sharing.
- Add CI pre-flight checks to ensure required secrets are present before running heavy steps.
- Add a small health-check after deployment (curl the app URL until HTTP 200).

---

If you want any of the recommendations implemented (README-only changes, playbook refactor to `community.docker`, or CI workflow normalization), tell me which item to do next and I will proceed.
