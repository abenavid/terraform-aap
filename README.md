# Terraform + Ansible + AAP demo

This repository separates **infrastructure** (`terraform/`), **orchestration and configuration** (`ansible/`), and leaves **secrets and cloud access** to Ansible Automation Platform (AAP) or your shell environment.

---

## The pattern (one playbook, one job)

**AAP runs a single Job Template** that executes **`ansible/tf_ops.yml`**. Nothing else is required for the happy path: no workflow of multiple jobs, no static inventory of EC2 IPs, no manual copy-paste from `terraform output`.

1. **Play 1 (`hosts: localhost`)** runs Terraform apply via the `cloud.terraform.terraform` module. Terraform creates the EC2 instance (and related AWS objects). The playbook registers the module result and reads **Terraform outputs** (`public_ips`, `private_ips`, `instance_ids`, `instance_names`, `instance_key_name`). A **debug** task prints names, IPs, and the EC2 **`instance_key_name`** so you can verify it matches your AAP Machine credential. It then calls **`ansible.builtin.add_host`** to put those hosts into an in-memory group **`tf_group_web_demo`** with **`ansible_host`** set to each public IP and **`ansible_user: ec2-user`**.

2. **Play 2 (`hosts: tf_group_web_demo`)** runs immediately in the **same playbook run**. It installs and configures the web stack (httpd, firewalld, templated `index.html`) on the instances Ansible just learned about.

3. **Play 3** (optional) pauses for manual checks before teardown when **`cleanup_after_test`** is **`true`**.

4. **Play 4** (optional) runs **`cloud.terraform.terraform`** with **`state: absent`** using the **same** `project_path`, **`force_init`**, **`complex_vars`**, and **variable map** as Play 1, so destroy matches apply. It prints instance IDs and public IPs from the apply result, then destroys. There are **no** tasks after destroy that target **`tf_group_web_demo`** (no SSH, validation, or fact gathering on those hosts).

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

The EC2 key pair is created from **public** key material. AAP can collect that with a **survey variable** (e.g. `ssh_public_key`), which the playbook passes to Terraform as **`web_demo_ssh_pubkey`**. That avoids `lookup('file')`, committed keys, or hardcoded `~/.ssh` paths.

**Play 2 SSH will fail** (`Permission denied (publickey,...)`) unless the **private** key side is correct:

- The **Job Template must attach a Machine credential** (SSH) in addition to the AWS cloud credential and survey.
- That **Machine credential must hold the private key** that matches the **same** public key you passed in the survey (the key pair Terraform registers on the EC2 instance).
- This playbook does **not** set `ansible_ssh_private_key_file`; AAP injects the key from the Machine credential. If the credential is missing, wrong, or does not match the surveyed public key, authentication fails even when Ansible can reach the host.

Never store private keys in this repo.

### Terraform state in AAP job pods

By default this project uses a **local** Terraform backend (`terraform.tfstate` next to the code). In many AAP execution environments, the job filesystem is **ephemeral**: the next run may have **no** previous state, so Terraform may try to create resources again or drift from what still exists in AWS.

**Mitigation used here (demo scope):**

- **Networking** does **not** rely on the account **default VPC**. Many AWS accounts (especially newer ones or locked-down orgs) have **no default VPC** in a region, so looking up `default = true` fails. The **recommended** path is to pass **`existing_vpc_id`** and **`existing_subnet_id`** for a VPC and subnet your team or lab already uses. If you omit both IDs, Terraform **auto-creates** a small VPC so the job does not fail with empty inputs—important because **AAP jobs are ephemeral** and **repeated runs** should stay resilient without a survey for every field. Optionally set **`create_vpc = true`** to force a new VPC even when you could reuse IDs. Creating VPCs counts against regional **VPC limits**, so prefer existing networking in shared accounts when you can.
- **Key pair naming** defaults to an auto-generated `name_prefix-key-<suffix>` so a fresh run without state is less likely to hit **InvalidKeyPair.Duplicate** against an old key left in AWS.

**Long-term fix:** use **remote state** (e.g. S3 + DynamoDB locking, Terraform Cloud, etc.) so every apply/destroy uses one source of truth. This repo keeps the backend simple on purpose; document your backend in your own environment.

---

## AWS networking (important)

This module supports **two modes**:

1. **Reuse existing VPC and subnet (recommended for demos)**  
   Set **`existing_vpc_id`** and **`existing_subnet_id`** (Terraform) or Ansible extra vars **`tf_existing_vpc_id`** and **`tf_existing_subnet_id`**. Leave **`create_vpc`** at **`false`** (default). The subnet should map public IPs if you need SSH/HTTP from the internet.

2. **Create a new VPC (fallback or explicit)**  
   - **Auto-fallback:** If **`create_vpc`** is **`false`** and **both** existing ID variables are **empty**, Terraform **creates** a VPC, public subnet, internet gateway, and routes automatically. That way a minimal AAP job (SSH key only) still works.  
   - **Explicit:** Set **`create_vpc`** to **`true`** to always create a new VPC stack (for example when you want isolation regardless of survey inputs).

You must **never** pass only one of **`existing_vpc_id`** / **`existing_subnet_id`**; Terraform validates that the pair is complete or both empty.

**Why auto-create helps:** Many accounts have **no default VPC**. **AAP jobs** often run with **no persistent workspace** and **minimal extra vars**, so requiring VPC IDs on every run breaks demos. Auto-creating when IDs are absent keeps applies reliable while still letting you pin to a shared VPC when you have the IDs.

The subnet you choose (or the one created) must allow what you need for the demo (for example **map public IP** on the subnet if you rely on the instance’s public address for SSH and HTTP from your client).

---

## Layout

| Path | Purpose |
|------|---------|
| **`terraform/`** | Infrastructure only: VPC (optional or auto), security group, key pair, EC2. |
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

**Preferred:** pass existing VPC and subnet (or set them in `ansible/vars/main.yml` / AAP extra vars).

**Minimal:** only `ssh_public_key`—Terraform will create a VPC if no IDs are provided (same defaults as `tf_create_vpc: false` with empty IDs).

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
# optional: AWS_SESSION_TOKEN, AWS_DEFAULT_REGION

ansible-playbook ansible/tf_ops.yml \
  -e 'ssh_public_key="ssh-ed25519 AAAA... your-comment"' \
  -e 'tf_existing_vpc_id=vpc-xxxxxxxx' \
  -e 'tf_existing_subnet_id=subnet-xxxxxxxx'
```

### Cleanup and destroy (`cleanup_after_test`)

Default in **`ansible/vars/main.yml`**: **`cleanup_after_test: true`**. That runs the full **create → verify (pause) → destroy** flow in one playbook run—like a clean unit test.

- **`cleanup_after_test: true`** (or `-e cleanup_after_test=true`): Play 3 pause runs, then Play 4 runs Terraform destroy with the **same** inputs as apply.
- **`cleanup_after_test: false`** (or `-e cleanup_after_test=false`): Skips the pause and **skips** destroy; AWS resources stay up after Play 2. Use this when you want to keep the environment for follow-up work.

**Terraform destroy only removes resources that exist in Terraform state** for this run’s workspace (`terraform.tfstate` beside the code, unless you use a remote backend). It does not delete arbitrary resources in your account—only what this configuration tracked.

**Apply and destroy in the same job** matters when using **local state**: each AAP job pod often has an **ephemeral filesystem**, so a later job may not see the same `terraform.tfstate`. Running apply and destroy in **one** playbook execution keeps state consistent so destroy targets what apply just created.

**AAP jobs are ephemeral**: the automation process ends when the job finishes; there is no long-lived “session.” The in-memory inventory from **`add_host`** exists only for that run—after destroy, nothing in this playbook tries to use **`tf_group_web_demo`** again.

**Destroy output** often lists **many** resources (instances, security groups, routes, optional VPC pieces, key pair, etc.). That is **expected**: Terraform walks the dependency graph and removes tracked objects. **If the log shows resources being destroyed and completes without error, the teardown path is behaving correctly.**

### Destroy only (Play 4) or CLI

For a **standalone** destroy (same networking inputs as apply):

```bash
ansible-playbook ansible/tf_ops.yml \
  --start-at-task "Terraform destroy (same module, path, and variables as apply)" \
  -e 'ssh_public_key="ssh-ed25519 AAAA... your-comment"' \
  -e 'tf_existing_vpc_id=vpc-xxxxxxxx' \
  -e 'tf_existing_subnet_id=subnet-xxxxxxxx'
```

Use the **same** networking mode as the apply that created the stack (same existing IDs, or empty IDs with auto-created VPC, or `tf_create_vpc: true`). Starting at the **block** task name runs the assert, pre-destroy debug (if `tf_apply` exists from an earlier play in the same run—usually run the full playbook), Terraform destroy, and success message.

Alternatively run **`terraform destroy`** from **`terraform/`** with the same **`terraform.tfvars`** or **`-var`** flags.

### Terraform CLI only (optional)

Requires **Terraform 1.5+** (for input checks).

```bash
cd terraform && terraform init && terraform apply
```

Use `terraform/terraform.tfvars.example` as a template. Never commit secrets or static AWS keys.

---

## Ansible Automation Platform

- **Execution environment:** Include **Terraform CLI 1.5+** and collections from `collections/requirements.yml` (see `execution-environment/`).
- **Job Template:** Single playbook **`ansible/tf_ops.yml`**, project root = repo root (or adjust `project_path` in the playbook if your layout differs).
- **Survey / extra vars:** `ssh_public_key` (SSH **public** key string); Terraform receives it as **`web_demo_ssh_pubkey`** and creates the EC2 key pair from it. Add **`tf_existing_vpc_id`** and **`tf_existing_subnet_id`** for the preferred path, or leave them empty for **auto VPC creation**. Set **`tf_create_vpc: true`** to force creating a new VPC. Optional **`cleanup_after_test`** (default **`true`**) controls whether Play 3–4 run (pause + Terraform destroy); set **`false`** to leave infrastructure running after Play 2.
- **AWS credential:** Type that injects environment variables **or** a role the job pod can assume (for Terraform).
- **Machine credential (required for Play 2):** Attach an SSH **Machine** credential whose **private key** is the pair of the survey **`ssh_public_key`**. The EC2 instance is launched with that key name/material; **without** a matching Machine credential, Play 2 fails SSH auth. After apply, Play 1 prints **`instance_key_name`** in a debug step—use it to confirm which AWS key pair the instance uses; it must align with your credential.

### SSH auth checklist

| Piece | Role |
|-------|------|
| Survey `ssh_public_key` | Public half; Terraform **`aws_key_pair`** + instance **`key_name`** |
| AAP Machine credential | Private half; must match the same key pair |
| Playbook | Sets **`ansible_host`** to the instance public IP and **`ansible_user: ec2-user`**; does not set a playbook-level private key path |

---

## Commands quick reference

| Step | Command |
|------|---------|
| Install collections | `ansible-galaxy collection install -r collections/requirements.yml` |
| Apply + configure + optional cleanup | `ansible-playbook ansible/tf_ops.yml -e 'ssh_public_key="..."'` (default: pause + destroy; add `-e cleanup_after_test=false` to leave infra up) |
| Destroy stack | Same playbook with `cleanup_after_test: true`, or `--start-at-task "Terraform destroy (same module, path, and variables as apply)"`, or `cd terraform && terraform destroy` |
| Terraform only | `cd terraform && terraform init && terraform apply` |
