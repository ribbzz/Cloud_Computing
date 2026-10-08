# Cloud Computing — CampusPulse 2026

Cloud-native smart campus prototype for EPITA's Big Data & Cloud Computing final project. CampusPulse ingests simulated room occupancy, energy, environmental and service-request events, classifies abnormal readings, and presents an operations dashboard with role-based access.

**Deployed demo:** https://cloud.learningtheory.xyz — requires a project account; credentials are not published. Availability depends on the demonstration resources remaining active.

## Implementation

- FastAPI backend and Nginx dashboard in Docker Compose on one Ubuntu EC2 instance in Europe (Paris).
- DynamoDB events/users tables and severity index; S3 logical backups and DynamoDB PITR.
- IAM instance credentials and an SSM SecureString JWT signing key.
- Staff, administrator and device roles with signed JWTs and salted PBKDF2 password hashes.
- Let's Encrypt HTTPS, HTTP redirect and a tested automatic-renewal reload hook.
- CloudWatch logs, metrics, dashboard and alarms; SNS email notifications; a $20 monthly budget.

## Repository map

| Path | Purpose |
| --- | --- |
| [campuspulse/app](campuspulse/app) | API, container build, interactive account creation/reset |
| [campuspulse/dashboard](campuspulse/dashboard) | Web dashboard and initial HTTP Nginx config |
| [campuspulse/simulator](campuspulse/simulator) | External sensor simulator with hidden password prompt |
| [campuspulse/deploy](campuspulse/deploy) | AWS provisioning scripts and IAM/monitoring templates |
| [campuspulse/ops](campuspulse/ops) | Deployment, HTTPS, backups and restore utilities |
| [Deployment guide](docs/DEPLOYMENT.md) | Prerequisites, fresh installation and existing-host updates |
| [Architecture](docs/ARCHITECTURE.md) | Deployed boundaries, data flow and limitations |
| [Validation record](docs/VALIDATION.md) | Observed live results and offline test instructions |
| [Operations](docs/OPERATIONS.md) | Accounts, monitoring, recovery and cleanup checklist |

## Verified demonstration

On October 8, 2026 the external simulator sent **58 events in 60 seconds, with 0 failed requests** over HTTPS. The application and CloudWatch showed **11 critical events and 7 warnings**. The critical-event alarm executed its SNS action and the email was received. Staff access to `/alerts` returned 403 while the administrator could view the populated alerts. Certificate renewal and the Nginx reload hook passed a dry run.

The measured restore exercise on September 2 restored 513 event records to a pre-created scratch table in 14.9 seconds. This is the data-copy duration, not a measured full infrastructure recovery time.

## Use the simulator

From your computer, with Python 3.12 or newer:

```bash
python campuspulse/simulator/simulate.py \
  --api https://cloud.learningtheory.xyz/api \
  --user sensor.fleet --rate 1 --duration 60 --anomaly 0.3
```

Enter the device account password at the hidden prompt. The October 8 validation used `ops.admin`, which also has ingestion permission. Obtain credentials from the project operator; there are no default production passwords.

## Scope and status

This repository contains the working prototype source and updated reproduction instructions. The [architecture diagram](docs/ARCHITECTURE.md) is available as an image, vector PDF and editable SVG with official service/technology artwork. A report review draft with embedded evidence has been prepared privately; the presentation is also prepared privately as PowerPoint/PDF with speaker notes. Actual team contributions, speaker assignments and rehearsal remain to be completed. Raw screenshots, email subscription links, private keys, passwords and AWS credentials are excluded from the public repository.

Provisioning scripts create billable resources and are intended for a fresh stack, not repeated execution against the existing demo. Account credits are not evidence that usage has no cost. The single EC2 host is not an automatically redundant deployment; a second subnet supports a future/manual recovery design.

## References

Project requirements: course brief, *Cloud Native Smart Campus Operations Platform*, S2 2026, Dr. Badre Bousalem.

Implementation references: [FastAPI](https://fastapi.tiangolo.com/), [Boto3](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html), [Docker Compose](https://docs.docker.com/compose/), [Nginx HTTPS](https://nginx.org/en/docs/http/configuring_https_servers.html), [Certbot](https://eff-certbot.readthedocs.io/en/stable/using.html), [Systems Manager instance permissions](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-instance-permissions.html).
