# A2 and A3 machine inventory

Keep actual host details in the ignored `instructions/login-credentials.txt`
and the selected test host in `config.local.yaml`.

For each host, record an alias, hardware/SKU, CPU architecture, access method,
CANN version, device availability, and any restrictions from the owner. Verify
reported hardware with `npu-smi` before using it for testing or profiling.

Use authorized root access only to provision or verify a personal account.
Confirm device and toolchain permissions as that account, and record the
result in the active task before building, deploying, or testing. Ask the
owner to resolve missing permissions.
