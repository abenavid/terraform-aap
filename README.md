# Terraform + Ansible + AAP demo

This repository separates **infrastructure** (`terraform/`), **orchestration and configuration** (`ansible/`), and leaves **secrets and cloud access** to Ansible Automation Platform (AAP) or your shell environment.

---

## The pattern (one playbook, one job)

**AAP runs a single Job Template** that executes **`ansible/tf_ops.yml`**. Nothing else is required for the happy path: no workflow of multiple jobs, no static inventory of EC2 IPs, no manual copy-paste from `terraform output`.

1. **Play 1 (`hosts: localhost`)** runs Terraform apply via the `cloud.terraform.terraform` module. Terraform creates the EC2 instance (and related AWS objects). The playbook registers the module result and reads **Terraform outputs** (`public_ips`, `private_ips`, `instance_ids`, `instance_names`). It then calls **`ansible.builtin.add_host`** to put those hosts into an in-memory group **`tf_group_web_demo`** with `ansible_host` set to each public IP.

2. **Play 2 (`hosts: tf_group_web_demo`)** runs immediately in the **same playbook run**. It installs and configures the web stack (httpd, firewalld, templated `index.html`) on the instances Ansible just learned about.

### Why this works

- **Terraform** owns AWS resource creation and exposes connection facts as **outputs**.
- **Ansible** consumes those outputs in memory and configures the hosts in the **same process**, so there is no hand-off file or second automation run.

### Why separate workflow jobs would not preserve `add_host` memory

`add_host` only affects the **in-memory inventory for the current playbook run**. A **different** AAP job (even in the same workflow) is a **new** Ansible process with an empty inventory unless you inject inventory another way (dynamic inventory, project inventory, survey, etc.). So “Terraform in job A, configure in job B” does **not** automatically see hosts added in job A.

### Why you do not need instance IPs up front

IPs do not exist until Terraform finishes. The playbook builds the EC2 portion of the inventory **after** apply, from outputs. You only need **`localhost`** (or implicit local) for Play 1; Play 2 targets are created dynamically.

### Why AWS credentials come from AAP (or the environment)

The Terraform AWS provider is configured **without** `aws_access_key_id` / `aws_secret_access_key` in `.tf` files. Credentials are expected from the standard AWS chain: environment variables, shared config files, or **instance / job role**—for example an **AWS cloud credential** on the AAP Job Template that exports `AWS_*` into the job environment. **Do not** pass AWS keys in playbook extra vars.

### Why the SSH **public** key comes from an AAP survey

The EC2 key pair is created from **public** key material. AAP can collect that with a **survey variable** (e.g. `ssh_public_key`), which the playbook passes to Terraform as `web_demo_ssh_pubkey`. That avoids `lookup('file')`, committed keys, or hardcoded `~/.ssh` paths. The matching **private** key for SSH access is supplied separately (machine credential, AAP credential, or local agent)—never stored in this repo.

### Terraform state in AAP job pods

By default this project uses a **local** Terraform backend (`terraform.tfstate` next to the code). In many AAP execution environments, the job filesystem is **ephemeral**: the next run may have **no** previous state, so Terraform may try to create resources again or drift from what still exists in AWS.

**Mitigation used here (demo scope):**

- **`use_default_vpc`** (default `true`) prefers the account **default VPC** and a subnet, which reduces hitting **VpcLimitExceeded** from creating many dedicated VPCs.
- **Key pair naming** defaults to an auto-generated `name_prefix-key-<suffix>` so a fresh run without state is less likely to hit **InvalidKeyPair.Duplicate** against an old key left in AWS.

**Long-term fix:** use **remote state** (e.g. S3 + DynamoDB locking, Terraform Cloud, etc.) so every apply/destroy uses one source of truth. This repo keeps the backend simple on purpose; document your backend in your own environment.

---

## Layout

| Path | Purpose |
|------|---------|
| **`terraform/`** | Infrastructure only: VPC (optional), security group, key pair, EC2. |
| **`ansible/`** | Orchestration: `tf_ops.yml` (Terraform + configuration in one playbook). |
| **`collections/`** | Galaxy collection pins (`ansible-galaxy collection install -r collections/requirements.yml`). |
| **`execution-environment/`** | Optional EE image with Terraform CLI + collections for AAP. |
| **`archive/`** | Older or alternate material. |

`ansible.cfg` points at `ansible/inventory/hosts.example.ini`, which lists **localhost** for Play 1. **EC2 hosts are not** checked into inventory; they are added with `add_host` after Terraform runs.

**`ansible/configure_web.yml` is retired.** Its tasks are **Play 2** inside `tf_ops.yml`. Use only `tf_ops.yml` for provision + configure.

---

## How to run

### Install collections

```bash
ansible-galaxy collection install -r collections/requirements.yml
```

### One playbook: Terraform + configure (from repo root)

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
# optional: AWS_SESSION_TOKEN, AWS_DEFAULT_REGION

ansible-playbook ansible/tf_ops.yml \
  -e 'ssh_public_key="ssh-ed25519 AAAA... your-comment"'
```

### Destroy (same Terraform state / variables as your last apply)

```bash
ansible-playbook ansible/tf_destroy.yml \
  -e 'ssh_public_key="ssh-ed25519 AAAA... your-comment"'
```

### Terraform CLI only (optional)

```bash
cd terraform && terraform init && terraform apply
```

Use `terraform/terraform.tfvars.example` as a template. Never commit secrets or static AWS keys.

---

## Ansible Automation Platform

- **Execution environment:** Include **Terraform CLI** and collections from `collections/requirements.yml` (see `execution-environment/`).
- **Job Template:** Single playbook **`ansible/tf_ops.yml`**, project root = repo root (or adjust `project_path` in the playbook if your layout differs).
- **Survey / extra vars:** `ssh_public_key` (public key string).
- **Credential:** AWS credential type that injects environment variables **or** a role the job pod can assume.
- **SSH to EC2:** Machine credential (or equivalent) whose private key matches the surveyed public key.

---

## Commands quick reference

| Step | Command |
|------|---------|
| Install collections | `ansible-galaxy collection install -r collections/requirements.yml` |
| Apply + configure | `ansible-playbook ansible/tf_ops.yml -e 'ssh_public_key="..."'` |
| Destroy stack | `ansible-playbook ansible/tf_destroy.yml -e 'ssh_public_key="..."'` |
| Terraform only | `cd terraform && terraform init && terraform apply` |
