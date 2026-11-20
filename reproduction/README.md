# Reproducing CODoH E2E experiments on IBM Cloud

The Terraform deployment places the client in Washington DC, the SGX proxy in Dallas, and the target in Toronto. Setup installs the pinned benchmark artifacts, IBM DCAP, and Unbound. [Original artifact](https://github.com/etclab/codoh-artifact/tree/4fd30adbd237100399e8ea5a3ed6378196695346)

## Provision and run

Use Bash, Terraform 1.5+, OpenSSH, `jq`, and `tar`. Export `IBMCLOUD_API_KEY` and confirm your account has VPC access, quota, and SGX availability. Terraform apply creates billable resources. [IBM SGX requirements](https://cloud.ibm.com/docs/vpc?topic=vpc-creating-virtual-server-with-confidential-computing-vpc)

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Set the resource group ID, operator IPv4 /32, and SSH public key path.
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=reproduction.tfplan
terraform -chdir=terraform apply reproduction.tfplan
./setup/prepare.sh
./runs/table3.sh
```

The commands below `runs/` and `analysis/` are standalone. `internal/` holds the shared and VM-side code.

The default SSH login is `ubuntu` with `~/.ssh/id_rsa`. Use `BENCH_SSH_USER` and `BENCH_SSH_KEY` to override those defaults on all three VMs.

If IBM reports `Key with fingerprint already exists`, look up the matching key ID in the affected VM's region and set it in `terraform.tfvars`, for example `existing_ssh_key_ids = { client = "KEY_ID" }`. Keep the current Terraform state and generate a fresh plan before applying again. Leave entries out for roles whose keys Terraform already created successfully. [IBM SSH key lookup](https://cloud.ibm.com/docs/vpc?topic=vpc-managing-ssh-keys)

- `./runs/table3.sh` runs C1–C5 with 10,000 queries per cold, Zipf, and warm workload.
- `./runs/batch-size.sh` runs C2 once and C5 at batch sizes 10, 20, 50, 100, 200, and 400, using the same three workloads and query counts. Its seven result directories share a run ID suffix. Rerun `./setup/prepare.sh` on existing VMs to upload the updated runner first.
- `./runs/smoke.sh` runs 250 warm queries per configuration.
- `./runs/plain.sh` runs C1, C2, and C4. To provision without SGX, set `enable_sgx = false` and select a regular proxy profile in your Terraform variables before applying.

## Results and teardown

Run the microbenchmarks on the prepared SGX proxy between end-to-end runs.

- `./runs/table4.sh` measures cryptographic operations in plain and SGX modes.
- `./runs/table5.sh` measures LRU and ORAM reads at capacities 256–2,048.
- `./runs/table6.sh` compares the upstream PathORAM and linear-scan benchmarks in SGX at capacities 256, 1,024, 4,096, and 16,384 with 4 KiB blocks. The pinned linear-scan benchmark stops at the matching entry.

Tables 4 and 5 use 10,000 iterations per trial. Table 6 uses 100 for PathORAM and 100,000 for linear scan because the shorter scans did not produce timings under EGo. All three collect raw logs and `medians.csv` with microseconds per operation, using three trials. [Paper methodology](https://www.petsymposium.org/popets/2026/popets-2026-0137.php)

Runs print their folder name and download results to `results/<experiment-name>-<run-id>/`, for example `results/table4-crypto-20261120T140000Z-12345/`. If the download is interrupted, pass the full folder name to `./analysis/collect.sh <experiment-name>-<run-id>`. To replot the authors’ archived results locally, install Git, Python 3, gnuplot, and Ghostscript, then run `./analysis/replot-reference.sh`.

Install Matplotlib locally for automatic plotting after the batch-size sweep and Tables 4–6. The microbenchmarks write `latency.pdf`, `latency.png`, and a paper-style `tableN.tex` into their result folders. The sweep writes its CSV and LaTeX tables and PDF and PNG plots to `results/batch-size-comparison-<sweep-id>/`. The LaTeX tables use `booktabs`.

To regenerate plots from downloaded results:

```bash
python3 analysis/plot-batch-size.py <sweep-id>
python3 analysis/plot-microbench.py results/<experiment-name>-<run-id>
```

The upstream plotter drops the first 1,000 queries of each workload. IBM placement, hardware, and EPC capacity differ from the authors’ Azure setup. The runner uses the upstream standard workload order and the authors’ default target build, which does not verify the SGX quote cryptographically.

```bash
terraform -chdir=terraform destroy
```
