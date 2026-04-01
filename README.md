# Terraform + Ansible + AAP demo

This repository separates **provisioning** (Terraform), **configuration** (Ansible), and **orchestration** (Ansible Automation Platform). Secrets do not belong in the repo: use environment variables locally or AAP credentials that inject AWS variables into the job environment.

---

## Layout

| Path | Purpose |
|------|---------|
| **`terraform/`** | Infrastructure provisioning: VPC, subnets, routing, security groups, key pair, EC2. |
| **`ansible/`** | Configuration and orchestration: Terraform via `tf_ops.yml`, node setup via `configure_web.yml`. |
| **`collections/`** | Galaxy collection pins required by the playbooks (`ansible-galaxy collection install -r collections/requirements.yml`). |
| **`execution-environment/`** | Optional: build a custom execution environment image with Terraform and collections for AAP or `ansible-navigator`. |
| **`archive/`** | Experimental or superseded material (alternate Terraform layout, old build context, optional navigator config). |

```
.
├── terraform/
│   ├── main.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── ansible/
│   ├── tf_ops.yml
│   ├── configure_web.yml
│   ├── vars/
│   │   └── main.yml
│   ├── templates/
│   │   └── index.html.j2
│   └── inventory/
│       └── hosts.example.ini
├── collections/
│   └── requirements.yml
├── execution-environment/
├── archive/
├── ansible.cfg
└── README.md
```

Copy `ansible/inventory/hosts.example.ini` to `ansible/inventory/hosts.ini` and set `ansible_host` from Terraform outputs. `hosts.ini` is gitignored so instance addresses stay local.

---

## How to run

### 1. Terraform (via Ansible)

Install collections, set AWS credentials in the environment, then run the Terraform wrapper playbook from the repo root:

```bash
ansible-galaxy collection install -r collections/requirements.yml

ansible-playbook ansible/tf_ops.yml \
  -e tf_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
```

Alternatively run Terraform directly from `terraform/` (`terraform init`, `terraform apply` with `ssh_public_key` and region variables). See `terraform/terraform.tfvars.example`.

### 2. Configure servers

Point inventory at your instances (copy `hosts.example.ini` → `hosts.ini`), then:

```bash
ansible-playbook ansible/configure_web.yml
```

---

## Prerequisites

- **Terraform CLI** (for direct applies) or rely on the EE image that includes Terraform when using AAP.
- **Ansible** with collections from `collections/requirements.yml`.
- **AWS credentials** in the environment (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optional `AWS_SESSION_TOKEN`, `AWS_DEFAULT_REGION`).
- **SSH**: Terraform uses the **public** key for the EC2 key pair; Ansible uses the **private** key to reach hosts.

---

## Ansible Automation Platform

- **Execution environment**: `./execution-environment/build-ee.sh` builds an image with Terraform and the pinned collections; push to a private registry for AAP jobs.
- **Credentials**: Attach a cloud credential that exports AWS environment variables into the job. Do not store keys in extra variables or project files.
- **SSH for `configure_web`**: Use machine credentials or a key stored in AAP, not committed to git.

---

## Commands quick reference

| Step | Command |
|------|---------|
| Install collections | `ansible-galaxy collection install -r collections/requirements.yml` |
| Apply via Ansible | `ansible-playbook ansible/tf_ops.yml -e tf_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"` |
| Apply Terraform only | `cd terraform && terraform init && terraform apply` |
| Configure nodes | `ansible-playbook ansible/configure_web.yml` |
