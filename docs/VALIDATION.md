# Validation record

## Live observations

The following results were observed during guided execution and recorded as screenshots/logs retained privately for the academic report. Raw email screenshots and subscription links are not published here.

| Date | Check | Observed result |
| --- | --- | --- |
| 2026-09-02 | API security/validation | Recorded 401 unauthenticated, 403 wrong role, 422 invalid event type, 201 accepted event |
| 2026-09-02 | S3 restore drill | 513 records copied to a pre-created scratch table in 14.876 s; count matched |
| 2026-10-07 | EC2 status / SSM | 3/3 status checks; SSM connected after required policy attachment and reboot |
| 2026-10-08 | TLS | Trusted certificate for cloud.learningtheory.xyz; HTTPS health returned 200 |
| 2026-10-08 | Redirect / renewal path | HTTP 308 to HTTPS; HTTP challenge test file remained accessible |
| 2026-10-08 | Renewal | Certbot dry run including deploy hook succeeded; timer displayed next scheduled run |
| 2026-10-08 | Staff authorization | Staff dashboard accessible; alerts panel denied with 403 |
| 2026-10-08 | Admin authorization | Admin dashboard and populated alerts accessible |
| 2026-10-08 | External HTTPS ingestion | 58 events / 60 s, 18 abnormal, 0 failed requests; authenticated as ops.admin |
| 2026-10-08 | Dashboard / metrics | 11 critical and 7 warning events in application and CloudWatch |
| 2026-10-08 | Alert delivery | Alarm changed OK → ALARM at 13:57:02 UTC; SNS action succeeded; email received |
| 2026-10-08 | Budget evidence | $20 monthly; actual >80% ($16) not exceeded; forecast >100% ($20) exceeded |

The simulator's rate is approximate: it sleeps after each request, so request latency reduces throughput. This run validates low-rate functionality and is not a stress test or a latency benchmark. A backup video is optional evidence; none is claimed here.

## Offline tests

From the repository root:

```bash
python3.12 -m venv .venv
.venv/bin/pip install -r campuspulse/app/requirements.txt -r campuspulse/tests/requirements.txt
.venv/bin/python -m pytest campuspulse/tests -q
```

Repository preparation validation: **6 offline tests passed**; Python/JSON/Bash syntax and Compose configuration checks passed; Nginx 1.27.5 accepted the HTTPS template using temporary test certificates.

Tests use dummy local credentials and mocked AWS services. They cover staff/admin/device access boundaries, invalid login and event validation, critical-event metric emission, and account creation/reset preserving roles and attributes. They do not prove a fresh deployment in AWS.

The API/dashboard source was retained from the demonstrated prototype. Repository preparation adds the interactive account helper, HTTPS packaging templates and operational fixes; those additions are locally validated and are not represented as already deployed on the live instance. The HTTPS behavior was applied and validated manually on the live host before packaging.

## Remaining academic deliverables

A 25-page report review PDF with embedded evidence has been prepared privately, and the architecture PDF/image/SVG exports are in docs/images. The report still needs actual team contributions. A 16-slide PowerPoint/PDF and speaker guide are prepared privately: twelve main slides timed to fifteen minutes plus four backup slides. Actual speaker assignments and rehearsal remain outstanding. This repository is the source/deployment-guide deliverable, not proof of submission to the instructor.
