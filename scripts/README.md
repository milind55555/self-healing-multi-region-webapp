# Operational scripts

`check-endpoints.sh` checks the public hostname's `/`, `/health`, and `/ready` endpoints. Run from a machine with curl and network access.

For failover testing, publish a synthetic CloudWatch alarm notification to the SNS topic only in a test environment. Never run an unreviewed failover test against production DNS.
