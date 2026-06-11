---
name: project-markdown-files-design
description: Design spec for writing Korean markdown blog posts for AWS cloud projects P2–P5, following the structure of AWS Cloud - project1.md
metadata:
  type: project
---

# Design: AWS Cloud Project Markdown Files (P2–P5)

**Status:** APPROVED
**Date:** 2026-06-11

---

## Context

`AWS Cloud - project1.md` exists in the repo root as a completed Korean-language blog post covering the P1 static website project. The goal is to produce equivalent files for P2–P5, using raw reference materials (chat logs, deployment notes, screenshots) as source content.

---

## Output Files

| File | Primary Source | Images | pubDate |
|---|---|---|---|
| `AWS Cloud - project2.md` | `ReferContext/p2.txt` | `../../assets/project/p2-img/` | `'Jun 12 2026'` |
| `AWS Cloud - project3.md` | `ReferContext/p3.txt` | `../../assets/project/p3-img/` | `'Jun 13 2026'` |
| `AWS Cloud - project4.md` | `ReferContext/p4.txt` | `../../assets/project/p4-img/` | `'Jun 14 2026'` |
| `AWS Cloud - project5.md` | `project5-document-engine/README.md` (EN→KO) | `../../assets/project/p5-img/` | `'Jun 15 2026'` |

Each file gets a different `pubDate` so the blog timeline looks natural. `tags` and `heroImage` follow the same pattern as P1 (e.g., `heroImage: '../../assets/project/p2-img/p2-title.png'`).

Frontmatter fields confirmed from `AWS Cloud - project1.md`:
```
title, description, pubDate, tags, heroImage
```

---

## Section Structure (per file)

Matches P1 section order. Each file must pass the **mandatory checklist** at the bottom before being marked complete.

1. **Frontmatter**
2. **소개** — 1–2 paragraph Korean intro
3. **아키텍처** — ASCII flow diagram
4. **주요 구성 요소** — Component table; include a **비용** column noting Free Tier status or estimated cost per service
5. **사전 준비** — Full IAM / AWS CLI / Terraform install instructions repeated verbatim from P1 (Option ①: standalone-readable; each post works without reading P1 first). Add any project-specific prerequisites after the common block (e.g., Gemini API key for P4, Bedrock model access for P5).
6. **배포 가이드** — Numbered steps with code blocks and screenshots
7. **테스트 시나리오** — Project-specific validation steps
8. **⚠️ 비용 관리** — Project-specific cost section (see table below)
9. **트러블슈팅 노트** — Real errors from ReferContext, scrubbed of PII
10. **인프라 삭제** — `terraform destroy` sequence
11. **기술 스택** — Inline tag list

### Cost section guidance per project

| Project | Cost focus |
|---|---|
| P2 | Textract subscription risk; SQS/Lambda within Free Tier |
| P3 | Cross-Region Replication S3 transfer costs; EBS snapshot storage |
| P4 | Gemini API call costs (~free at test scale); Bedrock per-token cost if switched |
| P5 | **OpenSearch ~$0.036/hr → ~$0.86/day** — destroy immediately after testing |

---

## Mandatory Per-File Checklist

Before marking any file complete, verify:

- [ ] **PII scrubbed** — no real email addresses, AWS account IDs, CloudFront distribution IDs, bucket names containing personal names, API keys, or IP addresses. Replace with `<your-email>`, `<distribution-id>`, `<your-suffix>`, etc.
- [ ] **Image filenames normalised** — all `![...]` references use lowercase-English-hyphenated filenames matching exactly what exists in `정리자료/p*-img/` (spaces → hyphens, Korean chars removed). Note: images will render as broken links until files are copied to `assets/`.
- [ ] **Cost section present** — project-specific cost note included
- [ ] **Prerequisites complete** — full IAM/CLI/Terraform block present (not linked to P1)
- [ ] **Frontmatter valid** — all 5 fields set, `pubDate` matches table above

---

## Language & Style

- **Korean** throughout (matching P1)
- Code blocks, AWS resource names, CLI commands remain in English
- Tone: approachable technical blog post, same register as P1
- Target length: ~80% of P1 volume per section (P1 is screenshot-heavy; these files lean on fewer images)

---

## Image Path Convention

```
../../assets/project/p2-img/<filename>
../../assets/project/p3-img/<filename>
...
```

Actual files currently live in `정리자료/p*-img/`. Markdown references the `assets/` path; images will appear broken in preview until files are copied. This is intentional and expected — note it in the completion report for each file.

---

## P5 Special Note

`ReferContext/p5.txt` is empty. P5 source is `project5-document-engine/README.md` (English). Translate to Korean, incorporate `정리자료/p5-img/` screenshots, and trim "Common Errors" to a concise troubleshooting table at P1 depth. The cost section must prominently flag OpenSearch as the primary cost driver.

---

## Execution Order & Review Gates

```
Write P2 → user reviews P2 → approved → Write P3 → user reviews P3 → ...
```

"Complete" means: user has reviewed and approved the file. Do not start the next file until the current one is explicitly approved.

---

## Out of Scope

- Moving/copying image files from `정리자료/` to `assets/`
- Publishing or deploying the blog
- Writing English versions
- Editing `AWS Cloud - project1.md`
- Adding new screenshots beyond what exists in `정리자료/`
