# Project Markdown Files (P2–P5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write four Korean-language blog post markdown files (`AWS Cloud - project2.md` through `project5.md`) matching the structure and style of the existing `AWS Cloud - project1.md`.

**Architecture:** Each file is written one at a time with a user review gate before proceeding to the next. Source material (raw chat logs in `ReferContext/`, screenshots in `정리자료/p*-img/`, and `project5-document-engine/README.md`) is distilled into clean Korean blog posts. Each file is self-contained — no links to other posts for prerequisites.

**Tech Stack:** Korean Markdown, Astro frontmatter, AWS (S3, Lambda, SQS, DynamoDB, OpenSearch, Bedrock, CloudFront, API Gateway, EventBridge, SNS, CloudWatch)

---

## File Map

| Action | Path |
|---|---|
| Create | `AWS Cloud - project2.md` |
| Create | `AWS Cloud - project3.md` |
| Create | `AWS Cloud - project4.md` |
| Create | `AWS Cloud - project5.md` |
| Spec | `docs/superpowers/specs/2026-06-11-project-markdown-files-design.md` |

---

## PII Patterns to Scrub (apply to ALL files)

Replace any occurrence of the following in every file before saving:

| Real value pattern | Replacement |
|---|---|
| Real email addresses | `your@email.com` |
| Real AWS Account IDs (12 digits) | `123456789012` |
| CloudFront distribution IDs (e.g. `E1LCZZEIFR74TF`) | `<distribution-id>` |
| API Gateway IDs (e.g. `vygoy0n7cg`) | `<api-id>` |
| S3 bucket names with personal names (e.g. `p2-pipeline-ingestion-jaehwan-20260528`) | `p2-pipeline-ingestion-<suffix>` |
| Lambda function ARNs | `<lambda-arn>` |
| Personal name suffixes (e.g. `jaehwan-20260528`) | `<your-name>-<date>` |

---

## Mandatory Per-File Checklist

Run before every commit:

- [ ] All 5 frontmatter fields present (`title`, `description`, `pubDate`, `tags`, `heroImage`)
- [ ] PII scrubbed per table above — grep for `@` signs, 12-digit numbers, real names
- [ ] 비용 관리 section present with project-specific cost info
- [ ] Prerequisites section contains full IAM/CLI/Terraform block (not a link to P1)
- [ ] All image paths use `../../assets/project/p*-img/<filename>` pattern
- [ ] Image filenames: no spaces, no Korean characters, no apostrophes (use hyphenated lowercase)

---

## Task 1: Write `AWS Cloud - project2.md`

**Source:** `ReferContext/p2.txt`
**Images available:** `정리자료/p2-img/` — `p2-upload-csv.png`, `p2-upload-csv-in-console.png`, `p2-upload-json-in-console.png`, `p2-upload-wrong-extension-in-console.png`, `p2-upload-pdf-in-log.png`, `p2-upload-pdf-in-log2.png`, `p2-Textract-incomplete-console.png`

**Files:**
- Create: `AWS Cloud - project2.md`

- [ ] **Step 1: Write the file**

Create `AWS Cloud - project2.md` with the following content:

```markdown
---
title: 'AWS Project2 - Serverless Data Pipeline'
description: 'AWS+Terraform로 구축한 서버리스 데이터 파이프라인에 대해 설명합니다.'
pubDate: 'Jun 12 2026'
tags: ["AWS", "Terraform", "Lambda", "SQS", "DynamoDB"]
heroImage: '../../assets/project/p2-img/p2-title.png'
---

# Project 2: Serverless Data Pipeline (S3 + SQS + Lambda × 3 + DynamoDB)

Terraform으로 구축한 서버리스 데이터 처리 파이프라인입니다. S3에 업로드된 파일의 확장자를 자동으로 감지하여 CSV/JSON은 DynamoDB에 저장하고, PDF/이미지는 pypdf·Rekognition으로 분석해 결과를 S3에 저장하며, 지원하지 않는 형식은 격리(Quarantine) 버킷으로 자동 이동합니다.

---

## 아키텍처

```
[파일 업로드]
  CSV / JSON / PDF / 이미지 → S3 (Ingestion)
                                      ↓
                               Lambda (Router)
                               ↓ 확장자 감지
              ┌────────────────┴───────────────┐
        SQS (정형 큐)                    SQS (비정형 큐)
              ↓                                 ↓
       Lambda (Parser)                 Lambda (Extractor)
              ↓                                 ↓
          DynamoDB                       S3 (Processed)
        (정형 데이터)                    (분석 결과 JSON)
                                                ↓ 오류 시
                                         S3 (Quarantine)

[CloudWatch (Lambda 오류·실행시간)]
        ↓
   SNS Topic ──── 이메일 알림
```

---

## 주요 구성 요소

| 리소스 | 설명 | 비용 |
|---|---|---|
| **S3 Ingestion Bucket** | 파일이 처음 업로드되는 버킷. S3 이벤트로 Router Lambda 트리거 | Free Tier 5GB |
| **S3 Processed Bucket** | pypdf·Rekognition 분석 결과 JSON 저장. 90일 후 자동 삭제 | Free Tier 5GB |
| **S3 Quarantine Bucket** | 지원하지 않는 확장자 파일 격리 보관 | Free Tier 5GB |
| **Lambda (Router)** | S3 이벤트·API Gateway 요청 수신 → 확장자 감지 → SQS 라우팅 | Free Tier 1M 요청/월 |
| **Lambda (Parser)** | SQS 정형 큐 소비 → CSV/JSON 파싱 → DynamoDB 저장 | Free Tier |
| **Lambda (Extractor)** | SQS 비정형 큐 소비 → PDF(pypdf) / 이미지(Rekognition) 분석 | Free Tier |
| **SQS 정형 큐** | CSV, JSON 파일 라우팅용 메시지 큐 | Free Tier 1M 메시지/월 |
| **SQS 비정형 큐** | PDF, 이미지 라우팅용 큐 (Visibility Timeout 300초) | Free Tier |
| **DynamoDB** | 정형 데이터 저장 (PAY_PER_REQUEST, 파티션 키: `record_id`) | Free Tier 25GB |
| **API Gateway** | 외부에서 직접 파이프라인을 트리거할 수 있는 HTTP 엔드포인트 | Free Tier 1M 호출/월 |
| **CloudWatch** | Lambda 오류율·실행시간 모니터링 + 대시보드 | Free Tier |
| **SNS** | 처리 오류 발생 시 이메일 알림 | Free Tier 1K 이메일/월 |

---

## 사전 준비

- AWS 계정
- IAM 사용자 (`terraform-admin`, `AdministratorAccess` 정책 부여, Access Key 발급 — CLI 전용)
    * 1단계: IAM 사용자 생성
    * 2단계: AdministratorAccess 권한 부여
    * 3단계: 액세스 키(Access Key) 발급 및 저장
    > ※ 화면에 비밀 액세스 키는 따로 적어두거나 csv 파일을 다운로드해 둘 것 — 재확인 불가

- AWS CLI v2

    ```bash
    # Linux / macOS
    brew install awscli
    aws --version
    ```

    ```powershell
    # Windows
    winget install Amazon.AWSCLI
    aws --version
    ```

- Terraform >= 1.x

    ```bash
    # Linux / macOS
    brew tap hashicorp/tap
    brew install hashicorp/tap/terraform
    terraform --version
    ```

    ```powershell
    # Windows
    winget install Hashicorp.Terraform
    terraform --version
    ```

> **설치 후 버전 확인 에러 시:** 터미널을 완전히 닫았다가 새로 열어서 다시 입력하세요. 환경 변수가 새로고침됩니다.

---

## 배포 가이드

### 1. AWS CLI 자격증명 등록

```bash
aws configure
# AWS Access Key ID:     <발급받은 Access Key ID>
# AWS Secret Access Key: <발급받은 Secret Access Key>
# Default region name:   ap-northeast-2
# Default output format: json
```

연결 확인:

```bash
aws sts get-caller-identity
```

### 2. 변수 설정 (`variables.tf`)

| 변수 | 설명 | 예시 |
|---|---|---|
| `suffix` | 전 세계에서 고유해야 하는 S3 버킷 이름 접미사 | `<your-name>-<date>` |
| `alert_email` | CloudWatch 알람을 받을 이메일 주소 | `your@email.com` |

### 3. Terraform 배포

```powershell
cd project2-serverless-pipeline
terraform init
terraform plan
terraform apply
```

### 4. Lambda 함수 확인

```powershell
aws lambda list-functions --query "Functions[*].FunctionName" --region ap-northeast-2
```

3개 함수(`router`, `parser`, `extractor`)가 목록에 보이면 정상 배포된 것입니다.

### 5. SNS 구독 확인 이메일 수신

배포 완료 후 `alert_email`로 **SNS Subscription Confirmation** 이메일이 옵니다. 메일 안의 **"Confirm subscription"** 링크를 클릭해야 오류 알림이 실제로 수신됩니다.

---

## 테스트 시나리오

> `terraform output`을 실행하면 아래 명령어에 실제 버킷 이름이 채워진 형태로 출력됩니다.

### ① 정형 데이터 — CSV 업로드

```powershell
aws s3 cp sample_data/test.csv s3://p2-pipeline-ingestion-<suffix>/test.csv
```

약 5~10초 후 DynamoDB에 데이터가 들어왔는지 확인:

```powershell
aws dynamodb scan --table-name p2-pipeline-records --region ap-northeast-2
```

![CSV 업로드 후 DynamoDB 확인](../../assets/project/p2-img/p2-upload-csv-in-console.png)

### ② 정형 데이터 — JSON 업로드

```powershell
aws s3 cp sample_data/test.json s3://p2-pipeline-ingestion-<suffix>/test.json
```

DynamoDB에 레코드가 추가되었는지 동일하게 확인합니다.

![JSON 업로드 확인](../../assets/project/p2-img/p2-upload-json-in-console.png)

### ③ 미지원 형식 — Quarantine 격리 확인

```powershell
echo "test" > sample_data/test.xyz
aws s3 cp sample_data/test.xyz s3://p2-pipeline-ingestion-<suffix>/test.xyz
```

격리 버킷 확인:

```powershell
aws s3 ls s3://p2-pipeline-quarantine-<suffix>/ --recursive
```

![미지원 파일 격리 확인](../../assets/project/p2-img/p2-upload-wrong-extension-in-console.png)

### ④ PDF 분석 — pypdf 추출 확인

```powershell
aws s3 cp sample_data/test.pdf s3://p2-pipeline-ingestion-<suffix>/test.pdf
```

약 10~15초 후 Processed 버킷에 JSON 결과가 생겼는지 확인:

```powershell
aws s3 ls s3://p2-pipeline-processed-<suffix>/results/ --recursive
```

![PDF 처리 CloudWatch 로그](../../assets/project/p2-img/p2-upload-pdf-in-log.png)

### ⑤ API Gateway 연동 확인

```powershell
$endpoint = terraform output -raw api_endpoint

$body = @{
    Records = @(@{
        s3 = @{
            bucket = @{ name = "p2-pipeline-ingestion-<suffix>" }
            object = @{ key = "test.csv"; size = 100 }
        }
    })
} | ConvertTo-Json -Depth 5 -Compress

Invoke-RestMethod -Uri $endpoint -Method Post `
  -Headers @{"Content-Type"="application/json"} `
  -Body $body
```

`message: "routing complete"` 응답이 오면 API Gateway 연동 성공입니다.

---

## ⚠️ 비용 관리

| 서비스 | Free Tier | 주의사항 |
|---|---|---|
| Lambda (×3) | 월 1M 요청 | 테스트 규모에서 과금 없음 |
| S3 (×3) | 5GB | 90일 라이프사이클로 Processed 버킷 자동 정리 |
| SQS (×2) | 월 1M 메시지 | 테스트 규모에서 과금 없음 |
| DynamoDB | 25GB | PAY_PER_REQUEST, 테스트 규모 무료 |
| API Gateway | 월 1M 호출 | 테스트 규모 무료 |
| CloudWatch | 기본 무료 | 로그 보관 7일 설정 권장 |

> 테스트 완료 후 `terraform destroy`로 리소스를 정리하세요.

---

## 트러블슈팅 노트

### 1. S3 Lifecycle 규칙 배포 오류

`aws_s3_bucket_lifecycle_configuration` 리소스의 `rule` 블록에 `filter`가 없으면 아래 오류가 발생합니다:

```
Error: "filter" or "prefix" must be specified
```

버킷 전체에 규칙을 적용하더라도 반드시 빈 `filter {}`를 명시해야 합니다:

```hcl
rule {
  id     = "auto-delete-after-90-days"
  status = "Enabled"
  filter {}   # ← 반드시 추가
  expiration { days = 90 }
}
```

### 2. API Gateway 요청 구조 차이

S3 이벤트에서 직접 호출할 때와 API Gateway를 거칠 때 Lambda `event` 구조가 다릅니다:

- **S3 직접 호출:** `event["Records"]`에 바로 접근 가능
- **API Gateway HTTP API v2:** 요청 본문이 `event["body"]`에 문자열로 래핑됨

Router Lambda에서 두 경로를 모두 처리하려면 시작부에 분기 처리를 추가합니다:

```python
if "body" in event:
    event = json.loads(event["body"]) if isinstance(event["body"], str) else event["body"]
```

### 3. PowerShell에서 curl.exe 사용 시 JSON 오류

PowerShell에서 `curl.exe -d '{"key": "val"}'`는 줄바꿈이 삽입되어 JSON이 깨집니다. `Invoke-RestMethod`와 `ConvertTo-Json`을 사용하는 것이 가장 안전합니다 (테스트 시나리오 ⑤ 참고).

### 4. Lambda 함수가 콘솔에서 보이지 않을 때

AWS 콘솔 우측 상단의 **리전이** `ap-northeast-2 (서울)`인지 확인하세요. 리전이 다르면 함수 목록이 비어 보입니다.

---

## 인프라 삭제

```powershell
# 각 S3 버킷을 먼저 비웁니다
aws s3 rm s3://p2-pipeline-ingestion-<suffix> --recursive
aws s3 rm s3://p2-pipeline-processed-<suffix> --recursive
aws s3 rm s3://p2-pipeline-quarantine-<suffix> --recursive

terraform destroy
```

---

## 기술 스택

`Terraform` · `AWS Lambda` · `AWS S3` · `AWS SQS` · `AWS DynamoDB` · `AWS API Gateway` · `AWS CloudWatch` · `AWS SNS` · `Python 3.12` · `pypdf` · `AWS Rekognition`
```

- [ ] **Step 2: Run mandatory checklist**

Verify before committing:
- Grep the file for `@` — no real email addresses
- Grep for 12-digit numbers — no real account IDs
- Grep for `jaehwan` or other real names — replace with `<suffix>`
- Confirm `pubDate: 'Jun 12 2026'` is set
- Confirm `비용 관리` section is present
- Confirm all image paths use `../../assets/project/p2-img/`
- Images listed: `p2-upload-csv-in-console.png`, `p2-upload-json-in-console.png`, `p2-upload-wrong-extension-in-console.png`, `p2-upload-pdf-in-log.png` — all filenames are already lowercase/hyphenated ✓

- [ ] **Step 3: Commit**

```powershell
git add "AWS Cloud - project2.md"
git commit -m "docs: add Korean blog post for P2 serverless data pipeline"
```

- [ ] **Step 4: User review gate**

Show the user the completed file and ask: *"P2 파일을 검토해 주세요. 수정할 내용이 있으면 알려주시면 반영하겠습니다. 괜찮으시면 P3 작성을 시작하겠습니다."*

Do NOT proceed to Task 2 until the user explicitly approves.

---

## Task 2: Write `AWS Cloud - project3.md`

**Source:** `ReferContext/p3.txt`
**Images available:** `정리자료/p3-img/` — `p3-Sub-cofirm-email.png`, `p3-Sub-cofirm-success-email.png`, `p3-ec2-SecurityGroup-ec2.png`, `p3-ec2-AZ.png`, `p3-snapshot-generate-check.png`, `p3-snapshot-generate-verification.png`, `p3-backup-success-verification-result-email.png`, `p3-restore-log.png`, `p3-restore-success-email.png`

**Files:**
- Create: `AWS Cloud - project3.md`

- [ ] **Step 1: Write the file**

```markdown
---
title: 'AWS Project3 - Smart Vault'
description: 'AWS+Terraform로 구축한 EC2 자동 백업·복구 시스템에 대해 설명합니다.'
pubDate: 'Jun 13 2026'
tags: ["AWS", "Terraform", "Lambda", "EventBridge", "EBS"]
heroImage: '../../assets/project/p3-img/p3-title.png'
---

# Project 3: Smart Vault — EC2 자동 백업·복구 시스템

Terraform으로 구축한 EC2 EBS 스냅샷 자동화 시스템입니다. `backup:true` 태그가 붙은 EC2 인스턴스를 매시간 자동으로 스냅샷 찍고, 7일 후 만료된 스냅샷은 새벽에 자동 삭제하며, 장애 시 API 호출 한 번으로 볼륨을 복구할 수 있습니다. 서울 리전 전체 장애에 대비해 싱가포르 리전으로 로그를 자동 복제합니다.

---

## 아키텍처

```
[자동 백업 흐름]
EventBridge (매시간) ──▶ Lambda (Backup)
                              ↓ backup:true 태그 EC2 탐색
                         EBS 스냅샷 생성
                         (RetainUntil = +7일 태그 자동 부여)
                              ↓ 완료 시
                         SNS ──── 이메일 알림

[자동 정리 흐름]
EventBridge (매일 새벽 2시) ──▶ Lambda (Cleanup)
                                      ↓ RetainUntil 만료 스냅샷 삭제
                                 S3 Archive (서울) ── 삭제 로그 저장
                                      ↓ 크로스 리전 복제
                                 S3 DR (싱가포르)

[수동 복구 흐름]
curl POST /restore ──▶ API Gateway ──▶ Lambda (Restore)
                                             ↓
                                      새 EBS 볼륨 생성
                                             ↓
                                      SNS ──── 복구 완료 이메일
```

---

## 주요 구성 요소

| 리소스 | 설명 | 비용 |
|---|---|---|
| **Lambda (Backup)** | `backup:true` 태그 EC2 탐색 → EBS 스냅샷 생성 → SNS 알림 | Free Tier |
| **Lambda (Cleanup)** | 만료 스냅샷 삭제 + S3 아카이브 로그 저장. DRY_RUN 모드 지원 | Free Tier |
| **Lambda (Restore)** | API Gateway 요청 → 스냅샷으로 새 EBS 볼륨 생성 → SNS 알림 | Free Tier |
| **EventBridge (×3)** | Backup: 매시간 / Backup daily: 매일 09시 / Cleanup: 매일 02시 KST | Free Tier |
| **S3 Archive (서울)** | Cleanup 삭제 로그 저장. 1년치 감사 기록 보관 | Free Tier 5GB |
| **S3 DR (싱가포르)** | 서울 버킷 크로스 리전 자동 복제. 재해 복구용 | ~$0.02/GB 전송 |
| **API Gateway** | Restore Lambda 트리거용 HTTP 엔드포인트. API 키 인증 | Free Tier |
| **SNS** | 백업 완료·복구 완료·오류 발생 시 이메일 알림 | Free Tier |
| **CloudWatch** | Lambda 실행 횟수·오류·S3 버킷 크기 대시보드 | Free Tier |

---

## 사전 준비

- AWS 계정
- IAM 사용자 (`terraform-admin`, `AdministratorAccess` 정책 부여, Access Key 발급 — CLI 전용)
    * 1단계: IAM 사용자 생성
    * 2단계: AdministratorAccess 권한 부여
    * 3단계: 액세스 키(Access Key) 발급 및 저장
    > ※ 화면에 비밀 액세스 키는 따로 적어두거나 csv 파일을 다운로드해 둘 것 — 재확인 불가

- AWS CLI v2

    ```bash
    # Linux / macOS
    brew install awscli
    aws --version
    ```

    ```powershell
    # Windows
    winget install Amazon.AWSCLI
    aws --version
    ```

- Terraform >= 1.x

    ```bash
    # Linux / macOS
    brew tap hashicorp/tap
    brew install hashicorp/tap/terraform
    terraform --version
    ```

    ```powershell
    # Windows
    winget install Hashicorp.Terraform
    terraform --version
    ```

---

## 배포 가이드

### 1. 변수 설정 (`variables.tf`)

```hcl
suffix      = "<your-name>-<date>"  # S3 버킷 이름 고유화 (필수)
alert_email = "your@email.com"      # SNS 알림 수신 이메일 (필수)
```

### 2. Terraform 배포

```powershell
cd project3-smart-vault
terraform init
terraform plan
terraform apply
```

### 3. SNS 구독 확인

배포 완료 후 `alert_email`로 오는 **Subscription Confirmation** 이메일의 링크를 클릭해야 알림이 활성화됩니다.

![SNS 구독 확인 이메일](../../assets/project/p3-img/p3-Sub-cofirm-email.png)

![구독 확인 완료](../../assets/project/p3-img/p3-Sub-cofirm-success-email.png)

### 4. 백업 대상 EC2에 태그 추가

`backup:true` 태그가 없으면 Backup Lambda가 인스턴스를 건너뜁니다. 아래 두 가지 방법 중 선택합니다.

**방법 A — `main.tf`에 테스트용 EC2 추가:**

```hcl
resource "aws_instance" "backup_target" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  tags = {
    Name   = "smart-vault-test-server"
    backup = "true"   # ← 이 태그 하나로 자동 백업 대상 등록
  }
}
```

**방법 B — 기존 인스턴스에 태그 추가:**

```powershell
aws ec2 create-tags `
  --resources <instance-id> `
  --tags Key=backup,Value=true
```

![EC2 가용 영역 확인](../../assets/project/p3-img/p3-ec2-AZ.png)

---

## 테스트 시나리오

### 1. Backup Lambda 수동 실행

AWS Lambda 콘솔에서 `p3-smart-vault-backup` 함수를 선택 → **Test** 버튼으로 수동 실행합니다.

EC2 콘솔 → **Snapshots**에서 `ManagedBy=smart-vault` 태그가 붙은 스냅샷이 생겼는지 확인합니다.

![스냅샷 생성 확인](../../assets/project/p3-img/p3-snapshot-generate-check.png)

![스냅샷 생성 검증](../../assets/project/p3-img/p3-snapshot-generate-verification.png)

백업 완료 이메일도 함께 확인합니다.

![백업 완료 이메일](../../assets/project/p3-img/p3-backup-success-verification-result-email.png)

### 2. Cleanup Lambda DRY_RUN 테스트

`variables.tf`에서 `cleanup_dry_run = true`로 설정한 상태로 Cleanup Lambda를 수동 실행합니다. CloudWatch Logs에 삭제 예정 목록이 출력되고 실제 삭제는 일어나지 않습니다. 확인 후 `false`로 바꾸고 `terraform apply`를 재실행하면 실제 삭제가 시작됩니다.

### 3. Restore API 호출

먼저 복구할 스냅샷 ID를 조회합니다:

```powershell
aws ec2 describe-snapshots `
  --owner-ids self `
  --filters "Name=tag:ManagedBy,Values=smart-vault" `
  --region ap-northeast-2 `
  --query "Snapshots[*].{ID:SnapshotId,Name:Tags[?Key=='Name']|[0].Value,State:State}" `
  --output table
```

Restore API 호출:

```powershell
$endpoint = (terraform output -raw restore_api_endpoint).Trim()
$apiKey   = (terraform output -raw restore_api_key_value).Trim()

Invoke-RestMethod -Method POST -Uri $endpoint `
  -Headers @{ "x-api-key" = $apiKey } `
  -ContentType "application/json" `
  -Body '{"snapshot_id":"<snap-id>","volume_type":"gp3","availability_zone":"ap-northeast-2a"}'
```

EC2 콘솔 → **Volumes**에서 `restored-snap-xxx` 이름의 새 볼륨이 생기고, 이메일로 복구 완료 알림이 옵니다.

![복구 로그 확인](../../assets/project/p3-img/p3-restore-log.png)

![복구 완료 이메일](../../assets/project/p3-img/p3-restore-success-email.png)

### 4. CloudWatch 대시보드 확인

```powershell
terraform output dashboard_url
```

출력된 URL을 브라우저에서 열면 Lambda 실행 횟수·오류·S3 버킷 크기를 한 화면에서 확인할 수 있습니다.

---

## ⚠️ 비용 관리

| 서비스 | Free Tier | 주의사항 |
|---|---|---|
| Lambda (×3) | 월 1M 요청 | 매시간 Backup 실행 = 월 744회 — 무료 범위 이내 |
| EBS Snapshot | 월 1GB 무료 | **테스트 후 수동 삭제 필수** — Terraform이 관리하지 않음 |
| S3 Archive (서울) | 5GB | 로그 파일은 매우 작음 |
| S3 DR (싱가포르) | - | **크로스 리전 복제 전송 ~$0.02/GB** — 로그 파일 소량이면 무시 가능 |
| EventBridge | 무료 | - |

> ⚠️ **EBS 스냅샷은 `terraform destroy`로 삭제되지 않습니다.** Lambda가 생성한 스냅샷은 EC2 콘솔 → Snapshots에서 `ManagedBy=smart-vault` 필터로 검색 후 수동 삭제해야 과금이 멈춥니다.

---

## 트러블슈팅 노트

### 1. Restore API가 400을 반환할 때

요청 본문에 `snapshot_id`가 없는 경우입니다. `Invoke-RestMethod`로 JSON 본문을 단일 문자열 변수에 담아 전송하면 해결됩니다 (테스트 시나리오 3 참고). `curl.exe`에 멀티라인 `-d` 인수를 사용하면 PowerShell이 줄바꿈을 삽입해 JSON이 깨집니다.

### 2. 기본 VPC가 없어 EC2 생성 실패

`terraform apply` 중 `InvalidSubnetID.NotFound` 오류가 발생하면 계정에 기본 VPC가 없는 것입니다. `main.tf`에 VPC/서브넷 데이터 소스를 추가하거나 AWS 콘솔에서 기본 VPC를 생성한 후 재실행합니다.

### 3. Cleanup Lambda가 스냅샷을 삭제하지 않음

`variables.tf`의 `cleanup_dry_run`이 `true`로 설정되어 있는지 확인하세요. `false`로 변경하고 `terraform apply`를 재실행해야 실제 삭제가 시작됩니다.

---

## 인프라 삭제

> ⚠️ Terraform이 직접 생성하지 않은 EBS 스냅샷은 수동으로 삭제해야 합니다.

```powershell
# 1. EBS 스냅샷 수동 삭제 (콘솔 또는 CLI)
aws ec2 describe-snapshots `
  --owner-ids self `
  --filters "Name=tag:ManagedBy,Values=smart-vault" `
  --region ap-northeast-2 `
  --query "Snapshots[*].SnapshotId" `
  --output text

# 각 스냅샷 ID에 대해 실행
aws ec2 delete-snapshot --snapshot-id <snap-id> --region ap-northeast-2

# 2. S3 버킷 비우기
aws s3 rm s3://p3-smart-vault-archive-<suffix> --recursive

# 3. Terraform 리소스 삭제
terraform destroy
```

---

## 기술 스택

`Terraform` · `AWS Lambda` · `AWS EventBridge` · `AWS EC2 / EBS` · `AWS S3` · `AWS API Gateway` · `AWS CloudWatch` · `AWS SNS` · `Python 3.12`
```

- [ ] **Step 2: Run mandatory checklist**

- Grep for `@` — no real emails
- Grep for real names (e.g. `jaehwan`) — replace with `<suffix>`
- Confirm `pubDate: 'Jun 13 2026'`
- Confirm `비용 관리` section with EBS snapshot and cross-region cost warnings
- Confirm all 9 image paths use `../../assets/project/p3-img/`
- All filenames already lowercase/hyphenated ✓

- [ ] **Step 3: Commit**

```powershell
git add "AWS Cloud - project3.md"
git commit -m "docs: add Korean blog post for P3 Smart Vault"
```

- [ ] **Step 4: User review gate**

Ask the user to review P3 before starting P4.

---

## Task 3: Write `AWS Cloud - project4.md`

**Source:** `ReferContext/p4.txt`
**Images available:** `정리자료/p4-img/` — `p4-terraform1.png`, `p4-terraform2.png`, `p4-terraform3.png`, `p4-terragrunt-complete.png`
(Skip `p4-terragrunt2-Gruntwork's public key.png` — apostrophe/space in filename causes URL encoding issues)

**Files:**
- Create: `AWS Cloud - project4.md`

- [ ] **Step 1: Write the file**

```markdown
---
title: 'AWS Project4 - AI Chatbot'
description: 'AWS+Terraform로 구축한 고객 서비스 AI 챗봇에 대해 설명합니다.'
pubDate: 'Jun 14 2026'
tags: ["AWS", "Terraform", "Lambda", "Bedrock", "Gemini", "DynamoDB"]
heroImage: '../../assets/project/p4-img/p4-title.png'
---

# Project 4: 고객 서비스 AI 챗봇 (API Gateway + Lambda + Gemini/Bedrock + DynamoDB)

Terraform으로 구축한 AI 기반 고객 서비스 챗봇입니다. Google Gemini API(또는 AWS Bedrock Claude)를 백엔드 AI 엔진으로 사용하며, DynamoDB에 대화 이력을 저장해 멀티턴 대화를 지원합니다. 욕설·에스컬레이션 감지 시 SNS로 이메일 알림을 보내고, 웹 UI는 CloudFront를 통해 HTTPS로 서빙됩니다.

> **배포 전제 조건:** P1·P2·P3 배포 불필요 — P4는 필요한 모든 AWS 리소스를 독립적으로 생성합니다.

---

## 아키텍처

```
[웹 UI]                  [REST API]
 브라우저                  curl / 외부 앱
    │                          │
    └──────────┬───────────────┘
               ▼
        API Gateway (HTTP v2)
               ▼
        Lambda (챗봇 로직)
        ┌──────────────────────────────────────┐
        │ 1. DynamoDB 대화 이력 조회 (최근 10턴) │
        │ 2. System Prompt + 이력 조립          │
        │ 3. AI 호출 (Gemini / Bedrock)         │
        │    └─ Gemini 키: SSM Parameter Store  │
        │       (Cold Start 시 1회 조회 후 캐시) │
        │ 4. 응답 검증/라우팅                    │
        │    (정상·에스컬레이션·욕설·fallback)    │
        │ 5. DynamoDB 대화 이력 저장 (TTL 24h)  │
        └──────────────────────────────────────┘
             │              │
        DynamoDB         Gemini API
        (대화 이력)       or Bedrock
             │
             ▼ (에스컬레이션 감지 시)
           SNS → 이메일 알림

웹 UI: S3 (비공개) ─ OAC ─▶ CloudFront (HTTPS)
```

---

## 주요 구성 요소

| 리소스 | 설명 | 비용 |
|---|---|---|
| **Lambda (챗봇)** | 대화 이력 조회 → AI 호출 → 응답 라우팅 → 이력 저장 | Free Tier 1M 요청/월 |
| **DynamoDB** | 세션별 대화 이력 저장 (TTL 24h 자동 만료) | Free Tier 25GB |
| **API Gateway (HTTP v2)** | 챗봇 REST 엔드포인트 (`POST /v1/chat`) | Free Tier 1M 호출/월 |
| **S3 + CloudFront** | 웹 UI 정적 파일 호스팅. OAC로 S3 비공개 유지 | S3 Free Tier, CF Free Tier |
| **SSM Parameter Store** | Gemini API 키 암호화 저장 (`SecureString`). Cold Start 시 1회 조회 후 캐시 | Free Tier |
| **SNS** | 에스컬레이션·욕설 감지 시 이메일 알림 | Free Tier 1K 이메일/월 |
| **CloudWatch** | 호출 수·응답 시간·오류율 대시보드 | Free Tier |

---

## 사전 준비

- AWS 계정
- IAM 사용자 (`terraform-admin`, `AdministratorAccess` 정책 부여, Access Key 발급 — CLI 전용)
    * 1단계: IAM 사용자 생성
    * 2단계: AdministratorAccess 권한 부여
    * 3단계: 액세스 키(Access Key) 발급 및 저장
    > ※ 화면에 비밀 액세스 키는 따로 적어두거나 csv 파일을 다운로드해 둘 것 — 재확인 불가

- AWS CLI v2

    ```bash
    # Linux / macOS
    brew install awscli
    aws --version
    ```

    ```powershell
    # Windows
    winget install Amazon.AWSCLI
    aws --version
    ```

- Terraform >= 1.x

    ```powershell
    # Windows
    winget install Hashicorp.Terraform
    terraform --version
    ```

- **Google Gemini API 키** (기본 AI 엔진)
    ```
    https://aistudio.google.com/apikey
      → "Create API Key" 클릭 → 키 복사 (AIzaSy... 형태)
    ```

---

## 배포 가이드

### Step 1. Gemini API 키를 SSM Parameter Store에 저장

```powershell
aws ssm put-parameter `
  --name "/cloud-portfolio/gemini-api-key" `
  --value "<your-gemini-api-key>" `
  --type SecureString `
  --region ap-northeast-2
```

> 이미 존재하는 경우 `--overwrite` 플래그를 추가하세요. Lambda는 Cold Start 시 이 경로에서 키를 읽고 컨테이너 수명 동안 캐시합니다.

### Step 2. `variables.tf` 수정

```hcl
suffix       = "<your-name>-<date>"  # S3 버킷 이름 고유화 (필수)
alert_email  = "your@email.com"      # 에스컬레이션 알림 수신 이메일 (필수)
company_name = "내 쇼핑몰"           # 챗봇에 표시될 서비스 이름 (선택)
```

> `gemini_api_key`는 `variables.tf`에 없습니다 — Step 1에서 SSM에 저장합니다.

### Step 3. 인프라 배포

```powershell
cd project4-ai-chatbot
terraform init
terraform plan
terraform apply
```

![Terraform apply 진행](../../assets/project/p4-img/p4-terraform1.png)

![Terraform apply 완료 1](../../assets/project/p4-img/p4-terraform2.png)

`terraform apply` 완료 후 출력값을 기록합니다:

```
chat_api_endpoint          = "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com/v1/chat"
chatbot_ui_url             = "https://<distribution-id>.cloudfront.net"
ui_upload_command          = "aws s3 sync ./website/ s3://p4-chatbot-ui-<suffix>/ --delete"
cache_invalidation_command = "aws cloudfront create-invalidation --distribution-id <distribution-id> --paths '/*'"
```

![Terraform apply 출력값](../../assets/project/p4-img/p4-terraform3.png)

### Step 4. 웹 UI에 API 엔드포인트 설정

`website/index.html`을 열어 아래 줄을 수정합니다:

```javascript
const API_ENDPOINT = "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com/v1/chat";
//                    ↑ Step 3에서 출력된 chat_api_endpoint 값으로 교체
```

### Step 5. 웹 UI S3 업로드 + CloudFront 캐시 무효화

```powershell
# Step 3 출력의 ui_upload_command 실행
aws s3 sync ./website/ s3://p4-chatbot-ui-<suffix>/ --delete

# Step 3 출력의 cache_invalidation_command 실행
aws cloudfront create-invalidation --distribution-id <distribution-id> --paths "/*"
```

### Step 6. 브라우저 접속

Step 3 출력의 `chatbot_ui_url`을 브라우저에서 열면 챗봇 UI가 표시됩니다.

---

## 테스트 시나리오

### 1. 기본 대화

```powershell
curl.exe -X POST "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com/v1/chat" `
  -H "Content-Type: application/json" `
  -d '{\"message\": \"반품 방법을 알려주세요.\", \"session_id\": \"test-001\"}'
```

예상 응답:
```json
{"response": "반품 정책 안내 메시지...", "session_id": "test-001", "escalated": false}
```

### 2. 대화 이력 연속성 확인

```powershell
# 1번째 메시지
curl.exe -X POST "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com/v1/chat" `
  -H "Content-Type: application/json" `
  -d '{\"message\": \"주문 번호는 12345입니다.\", \"session_id\": \"test-003\"}'

# 2번째 메시지 — 응답에 "12345"가 언급되면 이력 연동 성공
curl.exe -X POST "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com/v1/chat" `
  -H "Content-Type: application/json" `
  -d '{\"message\": \"제 주문 번호가 무엇인가요?\", \"session_id\": \"test-003\"}'
```

### 3. 에스컬레이션 트리거

```powershell
curl.exe -X POST "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com/v1/chat" `
  -H "Content-Type: application/json" `
  -d '{\"message\": \"상담원 연결해 주세요.\", \"session_id\": \"test-002\"}'
```

예상 응답: `"escalated": true` + `alert_email`로 이메일 알림 수신.

### 4. DynamoDB 대화 이력 확인

```powershell
aws dynamodb query `
  --table-name p4-chatbot-sessions `
  --key-condition-expression "session_id = :sid" `
  --expression-attribute-values "{\":sid\":{\"S\":\"test-003\"}}" `
  --region ap-northeast-2
```

---

## 검증 체크리스트

- [ ] `terraform output`에 `chat_api_endpoint`, `chatbot_ui_url` 출력 확인
- [ ] curl로 기본 대화 응답 확인 (`escalated: false`)
- [ ] 같은 `session_id` 연속 호출 시 이전 대화 기억 확인
- [ ] "상담원 연결" 요청 시 `escalated: true` + 이메일 알림 수신
- [ ] DynamoDB에 대화 이력 저장 확인
- [ ] 브라우저에서 CloudFront URL → 웹 UI 채팅 동작 확인

---

## ⚠️ 비용 관리

| 서비스 | Free Tier | 주의사항 |
|---|---|---|
| Lambda | 월 1M 요청 | 테스트 규모 무료 |
| DynamoDB | 25GB | TTL 24h 자동 만료로 데이터 누적 방지 |
| API Gateway | 월 1M 호출 | 테스트 규모 무료 |
| CloudFront | 월 1TB 전송 | 테스트 규모 무료 |
| Gemini API | 무료 쿼터 있음 | 기본 플랜 무료 범위 이내 — [Google AI Studio 확인](https://aistudio.google.com/) |
| Bedrock (선택) | 없음 | **Claude 사용 시 토큰당 과금** — 테스트 규모 $1~3/월 예상 |

> Bedrock으로 전환하려면 `variables.tf`에서 `ai_provider = "bedrock"`으로 변경 후 `terraform apply`를 재실행하세요. Claude 모델은 서울 리전 미지원으로 `bedrock_region = "us-east-1"`을 사용합니다.

---

## 트러블슈팅 노트

### 1. Gemini API 키 로딩 실패

Lambda가 SSM에서 키를 가져오지 못하면 `ParameterNotFound` 오류가 CloudWatch Logs에 남습니다. Step 1의 SSM 저장 명령어가 성공했는지, 파라미터 경로가 `/cloud-portfolio/gemini-api-key`인지 확인하세요.

### 2. 웹 UI가 이전 버전을 계속 보여줄 때

`aws s3 sync` 후 CloudFront 캐시가 남아있는 경우입니다. 캐시 무효화 명령어(Step 5)를 실행하면 전 세계 엣지에서 캐시가 5~10분 내 초기화됩니다.

### 3. Bedrock AccessDeniedException

Claude 모델은 AWS Marketplace 구독이 필요합니다. 구독 전에는 `AccessDeniedException: subscription required` 오류가 발생합니다. 구독 방법: AWS 콘솔 → Bedrock → Model catalog → Claude 모델 선택 → Subscribe.

---

## 인프라 삭제

```powershell
# S3 버킷 비우기
aws s3 rm s3://p4-chatbot-ui-<suffix> --recursive

# Terraform 리소스 삭제
terraform destroy

# SSM 파라미터는 Terraform이 관리하지 않으므로 수동 삭제
# AWS 콘솔 → Systems Manager → Parameter Store → /cloud-portfolio/gemini-api-key → 삭제
```

---

## 기술 스택

`Terraform` · `AWS Lambda` · `AWS API Gateway` · `AWS DynamoDB` · `AWS S3` · `AWS CloudFront` · `AWS SSM Parameter Store` · `AWS SNS` · `AWS CloudWatch` · `Google Gemini API` · `AWS Bedrock Claude` · `Python 3.12`
```

- [ ] **Step 2: Run mandatory checklist**

- Grep for real API IDs (e.g. `gt7zb6obp8`, `zwjpokvf9f`) — replaced with `<api-id>` ✓ (verify in written content)
- Grep for real distribution IDs — replaced with `<distribution-id>` ✓
- Grep for `jaehwan` — replaced with `<suffix>` ✓
- Confirm `pubDate: 'Jun 14 2026'`
- Confirm `비용 관리` section with Gemini/Bedrock cost note
- Skip `p4-terragrunt2-Gruntwork's public key.png` — not referenced ✓

- [ ] **Step 3: Commit**

```powershell
git add "AWS Cloud - project4.md"
git commit -m "docs: add Korean blog post for P4 AI chatbot"
```

- [ ] **Step 4: User review gate**

Ask the user to review P4 before starting P5.

---

## Task 4: Write `AWS Cloud - project5.md`

**Source:** `project5-document-engine/README.md` (English → Korean translation)
**Images available:** `정리자료/p5-img/`:
- `p5-terraform apply 12m50s.png` → reference as `p5-terraform-apply-12m50s.png`
- `p5-bedrock-Model-access.png` → `p5-bedrock-model-access.png`
- `p5-Create the OpenSearch Index.png` → `p5-create-the-opensearch-index.png`
- `p5-Create the OpenSearch vector index.png` → `p5-create-the-opensearch-vector-index.png`
- `p5-Upload PDF and watch CloudWatch logs.png` → `p5-upload-pdf-and-watch-cloudwatch-logs.png`
- `p5-verify dynamoDB and openSearch.png` → `p5-verify-dynamodb-and-opensearch.png`
- `p5-test query api&delete pdf.png` → `p5-test-query-api-and-delete-pdf.png`
- `p5-query test success.png` → `p5-query-test-success.png`

> ⚠️ All P5 image filenames have spaces/capitals/special characters. The markdown must use the **normalized** names above. Actual files in `정리자료/p5-img/` have the original names — they must be renamed when copied to `assets/`.

**Files:**
- Create: `AWS Cloud - project5.md`

- [ ] **Step 1: Write the file**

```markdown
---
title: 'AWS Project5 - Intelligent Document Analysis Engine'
description: 'AWS+Terraform로 구축한 RAG 기반 지능형 문서 분석 엔진에 대해 설명합니다.'
pubDate: 'Jun 15 2026'
tags: ["AWS", "Terraform", "Lambda", "OpenSearch", "Bedrock", "RAG"]
heroImage: '../../assets/project/p5-img/p5-title.png'
---

# Project 5: 지능형 문서 분석 엔진 (RAG 기반)

Terraform으로 구축한 RAG(Retrieval-Augmented Generation) 기반 문서 분석 엔진입니다. PDF를 S3에 업로드하면 pypdf로 텍스트를 추출하고, Bedrock Titan 임베딩으로 벡터화하여 OpenSearch에 색인합니다. 이후 자연어 질문을 받으면 벡터 유사도 검색으로 관련 청크를 찾아 Claude가 근거 기반 답변을 생성합니다.

> **독립 프로젝트:** P1–P4 배포 불필요 — P5는 모든 AWS 리소스를 독립적으로 생성합니다.

---

## 아키텍처 (RAG 패턴)

```
[문서 업로드 흐름]
  PDF → S3 → Lambda(Ingest)
               ↓ pypdf           ↓ 청크 분할
               텍스트 추출        500단어 단위
                    ↓
              Titan Embeddings  (텍스트 → 1024차원 벡터)
                    ↓
              OpenSearch Index  (벡터 저장)
                    ↓
              DynamoDB          (문서 메타데이터)

[질문 → 답변 흐름]
  질문 → API Gateway → Lambda(Query)
                             ↓
                       Titan Embeddings (질문 벡터화)
                             ↓
                       OpenSearch kNN 검색 (상위 5개 청크)
                             ↓
                       Bedrock Claude (청크 기반 답변 생성)
                             ↓
                       답변 + 출처 문서 반환
```

---

## 주요 구성 요소

| 리소스 | 설명 | 비용 |
|---|---|---|
| **S3** | PDF 문서 저장. 업로드 시 Ingest Lambda 자동 트리거 | Free Tier 5GB |
| **Lambda (Ingest)** | pypdf 텍스트 추출 → 청크 분할 → Titan 임베딩 → OpenSearch 색인 | Free Tier |
| **Lambda (Query)** | 질문 벡터화 → OpenSearch kNN 검색 → Claude 답변 생성 | Free Tier |
| **OpenSearch (t3.small)** | 1024차원 kNN 벡터 인덱스. 시맨틱 검색 엔진 | **⚠️ ~$0.036/hr (~$0.86/일)** |
| **DynamoDB** | 문서별 처리 상태·청크 수·문자 수 메타데이터 저장 | Free Tier 25GB |
| **API Gateway** | 외부 질문 수신 엔드포인트 (`POST /query`) | Free Tier |
| **Bedrock Titan Embeddings** | 텍스트 → 1024차원 벡터 변환 | ~$0.0001/1K 토큰 |
| **Bedrock Claude** | 검색된 청크 기반 답변 생성 | 토큰당 과금 (Haiku 최저가) |
| **SNS** | 문서 색인 완료·실패 이메일 알림 | Free Tier |
| **CloudWatch** | Lambda 호출·처리시간·OpenSearch 지연시간 대시보드 | Free Tier |

---

## 사전 준비

- AWS 계정 (결제 수단 등록 + 본인 인증 + 지원 플랜 선택 완료)
    > ⚠️ OpenSearch, Bedrock 등 프리미엄 서비스는 계정 완전 활성화(최대 24시간) 후 사용 가능합니다.

- IAM 사용자 (`terraform-admin`, `AdministratorAccess` 정책 부여, Access Key 발급)

- AWS CLI v2

    ```bash
    # Linux / macOS
    brew install awscli
    aws --version
    ```

    ```powershell
    # Windows
    winget install Amazon.AWSCLI
    aws --version
    ```

- Terraform >= 1.x

    ```powershell
    # Windows
    winget install Hashicorp.Terraform
    terraform --version
    ```

- **Bedrock 모델 접근** (배포 전 확인)

    AWS가 "Model access" 콘솔 페이지를 폐지했습니다. 현재 모델 접근 방식:

    - **Titan Embeddings (`amazon.titan-embed-text-v2:0`):** 서버리스, 첫 호출 시 자동 활성화. 별도 설정 불필요.
    - **Claude (Haiku 4.5 기본값):** AWS Marketplace 구독이 필요합니다. 구독 방법: Bedrock 콘솔 → Model catalog → Claude Haiku 4.5 → Subscribe (관리자 권한 필요).

    모델이 호출 가능한지 미리 확인:

    ```powershell
    '{"anthropic_version":"bedrock-2023-05-31","max_tokens":20,"messages":[{"role":"user","content":"Say OK"}]}' | Out-File -Encoding utf8 t.json
    aws bedrock-runtime invoke-model `
      --model-id us.anthropic.claude-haiku-4-5-20251001-v1:0 `
      --body fileb://t.json `
      --content-type application/json `
      --region us-east-1 out.json
    cat out.json
    ```

    ![Bedrock 모델 접근 확인](../../assets/project/p5-img/p5-bedrock-model-access.png)

---

## 배포 가이드

### Step 1. `variables.tf` 수정

```hcl
suffix      = "<your-name>-<date>"  # 리소스 이름 고유화 (필수)
alert_email = "your@email.com"      # SNS 알림 이메일 (필수)
```

### Step 2. 인프라 배포

```powershell
cd project5-document-engine
terraform init
terraform plan
terraform apply
```

> OpenSearch 프로비저닝에 **10~15분** 소요됩니다. 완료까지 기다리세요.

![Terraform apply 완료 (약 12분 50초)](../../assets/project/p5-img/p5-terraform-apply-12m50s.png)

### Step 3. OpenSearch 인덱스 생성

> ⚠️ **반드시 PDF 업로드(Step 4) 전에 인덱스를 먼저 생성하세요.** 문서가 먼저 업로드되면 OpenSearch가 `embedding` 필드를 일반 `float` 배열로 자동 생성해버려 kNN 검색이 실패합니다.

**Windows (PowerShell):**

```powershell
$ENDPOINT = terraform output -raw opensearch_endpoint
$KEY      = aws configure get aws_access_key_id
$SECRET   = aws configure get aws_secret_access_key

curl.exe -X PUT "$ENDPOINT/documents" `
  --aws-sigv4 "aws:amz:us-east-1:es" `
  --user "${KEY}:${SECRET}" `
  -H "Content-Type: application/json" `
  -d "@index-mapping.json"
```

예상 응답:
```json
{"acknowledged": true, "shards_acknowledged": true, "index": "documents"}
```

![OpenSearch 인덱스 생성](../../assets/project/p5-img/p5-create-the-opensearch-index.png)

![OpenSearch 벡터 인덱스 확인](../../assets/project/p5-img/p5-create-the-opensearch-vector-index.png)

### Step 4. 테스트 PDF 생성 및 업로드

```powershell
cd sample_docs
pip install reportlab
python create_sample_pdf.py
cd ..

$BUCKET = terraform output -raw documents_bucket
aws s3 cp sample_docs\sample.pdf s3://$BUCKET/sample.pdf
```

CloudWatch 로그로 처리 확인:

```powershell
aws logs tail /aws/lambda/p5-doc-engine-ingest --follow --region us-east-1
```

![PDF 업로드 및 CloudWatch 로그](../../assets/project/p5-img/p5-upload-pdf-and-watch-cloudwatch-logs.png)

예상 로그:
```
[Ingest] 처리 시작: s3://[bucket]/sample.pdf
[Ingest] 텍스트 추출 완료: NNN자
[Ingest] 청크 분할 완료: N개
[Ingest] ✅ 완료: N개 청크 색인
```

### Step 5. 처리 결과 검증

```powershell
# DynamoDB 메타데이터 확인
aws dynamodb scan `
  --table-name p5-doc-engine-documents `
  --region us-east-1 `
  --query "Items[*].{status:status.S, chunks:chunk_count.N, source:source_key.S}" `
  --output table
```

`status=completed`, `chunks > 0`이면 정상입니다.

![DynamoDB 및 OpenSearch 검증](../../assets/project/p5-img/p5-verify-dynamodb-and-opensearch.png)

---

## 테스트 시나리오 — RAG 질의응답

```powershell
$API = terraform output -raw query_api_endpoint

Invoke-RestMethod -Uri $API -Method POST -ContentType "application/json" `
  -Body '{"question": "What was the Q4 revenue?"}'
```

예상 응답:
```json
{
  "answer": "According to the document, the Q4 revenue reached $2,000,000...\n\nSources: sample.pdf",
  "sources": ["sample.pdf"],
  "chunks_used": 5,
  "question": "What was the Q4 revenue?"
}
```

**시맨틱 검색 검증** — 다른 표현으로 동일 내용 검색:

```powershell
Invoke-RestMethod -Uri $API -Method POST -ContentType "application/json" `
  -Body '{"question": "How much did the cloud migration save?"}'
```

![질의응답 테스트 성공](../../assets/project/p5-img/p5-query-test-success.png)

![테스트 쿼리 및 PDF 삭제](../../assets/project/p5-img/p5-test-query-api-and-delete-pdf.png)

---

## ⚠️ 비용 관리

| 서비스 | Free Tier | 주의사항 |
|---|---|---|
| **OpenSearch (t3.small)** | 없음 | **~$0.036/hr → ~$0.86/일** — 테스트 후 즉시 destroy |
| Lambda (×2) | 월 1M 요청 | 무료 |
| S3 | 5GB | 무료 |
| DynamoDB | 25GB | 무료 |
| Titan Embeddings | 없음 | ~$0.0001/1K 토큰 — 테스트 규모 무시 가능 |
| Claude Haiku 4.5 | 없음 | ~$1/$5 per 1M in/out 토큰 — 테스트 규모 $0.01 미만 |

> **OpenSearch가 가장 큰 비용입니다.** 테스트 직후 `terraform destroy`를 실행하세요. 하루 방치하면 약 $0.86가 발생합니다.

---

## 트러블슈팅 노트

### 1. kNN 검색 HTTP 400 오류

OpenSearch 인덱스가 Step 4 이전에 자동 생성된 경우입니다. `embedding` 필드가 `knn_vector`가 아닌 `float`로 매핑됩니다. 인덱스를 삭제하고 재생성하세요:

```powershell
curl.exe -X DELETE "$ENDPOINT/documents" --aws-sigv4 "aws:amz:us-east-1:es" --user "${KEY}:${SECRET}"
curl.exe -X PUT "$ENDPOINT/documents" --aws-sigv4 "aws:amz:us-east-1:es" --user "${KEY}:${SECRET}" `
  -H "Content-Type: application/json" -d "@index-mapping.json"
```

이후 PDF를 다시 업로드합니다.

### 2. Bedrock AccessDeniedException

두 가지 원인이 있습니다:

1. **IAM 권한 부족** — Lambda 역할이 `inference-profile/` ARN과 `foundation-model/` ARN 모두에 `bedrock:InvokeModel`을 허용해야 합니다 (`iam.tf` 확인).
2. **Marketplace 미구독** — Claude Haiku 4.5는 구독이 필요합니다. 구독 불가 시 `us.anthropic.claude-opus-4-5-20251101-v1:0`으로 대체하세요 (더 비쌈).

### 3. 응답이 영어로 나올 때

정상입니다. 쿼리 Lambda의 RAG 프롬프트가 영어로 작성되어 있어 Claude가 영어로 응답합니다.

### 4. OpenSearch 도메인이 이미 존재한다는 오류

이전 `terraform destroy`가 완전히 완료되지 않은 경우입니다. OpenSearch 삭제는 비동기로 5~10분 소요됩니다. AWS 콘솔 → OpenSearch → Domains에서 도메인이 완전히 삭제된 후 재시도하세요.

---

## 인프라 삭제

> **테스트 직후 즉시 실행하세요 — OpenSearch는 ~$0.86/일 과금됩니다.**

```powershell
$BUCKET = terraform output -raw documents_bucket
aws s3 rm s3://$BUCKET --recursive
terraform destroy
```

삭제 완료 후 AWS 콘솔에서 OpenSearch 도메인이 사라졌는지 확인합니다 (비동기 삭제로 수 분 소요):
```
AWS 콘솔 → OpenSearch → Domains → p5-doc-engine 도메인 없음 확인
```

---

## What is RAG?

RAG(Retrieval-Augmented Generation)는 AI가 학습 데이터에만 의존하지 않고 **실제 문서에서 근거를 찾아 답변**하는 패턴입니다.

```
일반 AI: 학습 데이터 기반 답변 → 환각(Hallucination) 위험
RAG:     문서 검색 → 근거 기반 답변 → 정확도 향상
```

P5 구현 방식:
1. 문서 → 벡터 임베딩 (의미를 숫자로 인코딩)
2. 질문 → 벡터 임베딩
3. 벡터 유사도로 관련 단락 검색
4. Claude가 검색된 단락에 근거해 답변 생성

---

## 기술 스택

`Terraform` · `AWS Lambda` · `AWS S3` · `AWS OpenSearch` · `AWS DynamoDB` · `AWS API Gateway` · `AWS Bedrock` · `Titan Embeddings V2` · `Claude Haiku 4.5` · `AWS SNS` · `AWS CloudWatch` · `Python 3.12` · `pypdf`
```

- [ ] **Step 2: Run mandatory checklist**

- Grep for real account IDs — replace with `123456789012`
- Grep for `@` — no real emails
- Confirm all P5 image paths use normalized filenames (hyphens, lowercase) ✓
- Confirm OpenSearch cost prominently flagged in `비용 관리` section ✓
- Confirm `pubDate: 'Jun 15 2026'`
- Note in completion report: *"P5 이미지 파일명에 공백/대문자/특수문자 포함 — assets/에 복사할 때 파일명 정규화 필요 (예: `p5-terraform apply 12m50s.png` → `p5-terraform-apply-12m50s.png`). 복사 전까지 이미지는 깨진 링크로 표시됩니다."*

- [ ] **Step 3: Commit**

```powershell
git add "AWS Cloud - project5.md"
git commit -m "docs: add Korean blog post for P5 document analysis engine (RAG)"
```

- [ ] **Step 4: Final review gate**

Ask the user to review P5 and confirm all 4 files are complete.

---

## Self-Review Against Spec

**Spec coverage check:**

| Spec requirement | Covered by |
|---|---|
| Korean language | All 4 tasks ✓ |
| Matches P1 section structure (10 sections) | All tasks include all 10 sections ✓ |
| PII scrubbing mandatory checklist | Step 2 of each task ✓ |
| Prerequisites full block (not linked) | All 4 files include full IAM/CLI/Terraform block ✓ |
| 비용 관리 section per file | All 4 tasks ✓ |
| Image paths `../../assets/project/p*-img/` | All image references use this pattern ✓ |
| pubDates staggered Jun 12–15 | Task 1–4 frontmatter ✓ |
| User review gate between files | Step 4 of each task ✓ |
| P5 from README.md (EN→KO) | Task 4 ✓ |
| P5 Common Errors trimmed to table | P5 트러블슈팅 is concise table-style ✓ |
| Image filename normalization note | Task 4 Step 2 ✓ |
| Broken-link disclaimer in completion report | Task 4 Step 2 ✓ |

**Placeholder scan:** No TBDs, TODOs, or "similar to Task N" patterns found.

**Type consistency:** No code functions defined — content-only plan, N/A.
