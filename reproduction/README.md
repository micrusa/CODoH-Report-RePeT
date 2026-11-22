# CODoH Reproduction on IBM Cloud

**Report:** [Reproduction Report (PDF)](../reproduction_report/report-template.pdf)

Replicates the [CODoH artifact](https://github.com/etclab/codoh-artifact/tree/4fd30adbd237100399e8ea5a3ed6378196695346) on three IBM Cloud VMs (client in `us-east`, SGX proxy in `us-south`, target in `ca-tor`).

## Reproducing

**Prerequisites:** Bash, Terraform 1.5+, OpenSSH, `jq`, `tar`, Python 3 with Matplotlib, and an IBM Cloud API key exported as `IBMCLOUD_API_KEY` (or run `ibmcloud login` and `source ./create-api-key.sh`).

### Provision

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Set resource_group_id, operator_cidr (/32), and ssh_public_key_file
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=reproduction.tfplan
terraform -chdir=terraform apply reproduction.tfplan
./setup/prepare.sh
```

By default SSH uses `ubuntu` and `~/.ssh/id_rsa` (override with `BENCH_SSH_USER` and `BENCH_SSH_KEY`).

### Run experiments

| Script | Report Table(s) | Experiment |
| --- | --- | --- |
| `./runs/table3.sh` | Table 2 | End-to-end latency across C1–C5 (Cold, Zipf, Warm) |
| `./runs/table4.sh` | Table 3 | Cryptographic operations in plain and SGX modes (10k ops) |
| `./runs/table4_1M_ops.sh` | Table 4 | Cryptographic operations in plain and SGX modes (1M ops, warmup trial + 5 trials) |
| `./runs/table5.sh` | Table 5, Figure 1 | Cache read latency (LRU vs. ORAM plain/SGX), 5 trials |
| `./runs/table6.sh` | Section 3.4 | Initial PathORAM vs. linear scan run (not tabulated due to 1 ms enclave clock step) |
| `./runs/table6_1M_ops.sh` | Table 6 | PathORAM vs. linear scan under SGX (1M ops, warmup trial + 5 trials) |
| `./runs/batch-size.sh` | Tables 7 & 8 | C5 batch-size sweep (`B ∈ {10, 20, 50, 256}`, `p = 0.1`, 5 trials) |
| `./runs/batch-size-plus-probability.sh` | Table 9 | C5 batch-size sweep with constant insertion budget (`p = 1/B`, 5 trials) |

### Destroy

```bash
terraform -chdir=terraform destroy
```

## Results

| Report Table | Description | Result Folder |
| --- | --- | --- |
| Table 2 | End-to-end latency (C1–C5) | [`results/table3-e2e-20261120T143950Z-16482/`](results/table3-e2e-20261120T143950Z-16482/) |
| Table 3 | Cryptographic operations (10k ops) | [`results/table4-crypto-20261120T133543Z-112714/`](results/table4-crypto-20261120T133543Z-112714/) |
| Table 4 | Cryptographic operations (1M ops) | [`results/table4-1m-20261122T102039Z-33581/`](results/table4-1m-20261122T102039Z-33581/) |
| Table 5, Figure 1 | Cache read latency | [`results/table5-cache-reads-20261122T111252Z-84017/`](results/table5-cache-reads-20261122T111252Z-84017/) |
| Section 3.4 | Initial PathORAM vs. linear scan (not tabulated) | [`results/table6-oram-vs-linear-scan-20261120T133701Z-113249/`](results/table6-oram-vs-linear-scan-20261120T133701Z-113249/) |
| Table 6 | PathORAM vs. linear scan (1M ops) | [`results/table6-1m-20261122T111409Z-84991/`](results/table6-1m-20261122T111409Z-84991/) |
| Tables 7 & 8 | Batch-size latency & cache hit rates (`p = 0.1`) | [`results/batch-size-comparison-20261121T090954Z-28651/`](results/batch-size-comparison-20261121T090954Z-28651/) (raw trials: `results/batch-size-c5-b*-trial*-20261121T090954Z-28651/`) |
| Table 9 | Batch-size sweep with `p = 1/B` | *Pending* (`results/batch-size-plus-probability-comparison-<sweep-id>/`) |
