This repo contains my work for the Reproducibility and Performance of Privacy-Enhancing Technologies seminar in my Erasmus/SEMP stay at University of Basel.

## [**Privacy and Performance Trade-offs in Cacheable Oblivious DNS over HTTPS**](report-template.pdf)

Oblivious DNS over HTTPS (ODoH) improves DNS privacy by separating users' identities from their queries. However, this prevents intermediary proxies from caching responses, increasing DNS resolution latency. Cacheable Oblivious DNS over HTTPS (CODoH) addresses this limitation by introducing privacy-preserving caching.

In this report, we examine CODoH's design and its privacy-enhancing mechanisms. We also analyze the performance results reported by its authors, which show substantial latency reductions for simulated common workloads while maintaining similar performance for uncached queries, at the cost of additional network traffic and processing overhead.

In addition, we analyze the overhead of Intel SGX and Path ORAM in cache-related operations.

## [**Replicating CODoH End-to-End experiments on IBM Cloud and analyzing Batch Size effect on latency.**](reproduction_report/report-template.pdf)

Batching in CODoH introduces a trade-off between performance and privacy: it delays cache insertion, potentially reducing cache hits and increasing cache misses, and it protects against set-difference attacks by mixing queries from more clients. Niroula et al (2026)'s experiments only tested end-to-end latency of CODoH using a batch size of B=10.

In addition, the experiments were performed on three Microsoft Azure virtual machines, where the SGX-capable one is no longer available, making it impossible to reproduce the original experiments. Moreover, Azure heavily restricts Intel SGX-enabled VMs, only available in selected regions and with specific quotas, and Azure has stopped allowing new subscriptions to deploy DCsv3/DCdsv3 instances, further limiting experimentation with Intel SGX.

Therefore, this report aims to (1) replicate Niroula et al (2026)'s experiments on IBM Cloud, using VM specifications as close as possible to the original experiments and (2) analyze the impact of Batch Size on end-to-end latency in a full CODoH configuration.

[Documentation for reproducing the replication & batch size experiments](./reproduction/README.md)
