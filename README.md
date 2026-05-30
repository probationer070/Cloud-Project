# Project 3: 지능형 자동 백업 (Smart Vault)

## 아키텍처
```
[EventBridge 스케줄러]
  매시간  ──────────────────────────────────┐
  매일 자정 ─────────────────────────────┐  │
  매일 새벽 2시 (KST) ────────┐          │  │
                               │          │  │
                        Cleanup Lambda  Backup Lambda
                        만료 스냅샷 삭제   ↓
                               │     EC2 (backup:true 태그)
                               │          ↓
                               │     EBS 스냅샷 생성 (증분)
                               │          ↓
                               │     태그 자동 부여
                               │    (날짜/환경/RetainUntil)
                               ↓
                        S3 아카이브 버킷 ──→ S3 DR 버킷 (크로스 리전)
                               ↓
                           SNS 알림 → 이메일

[API Gateway]
  POST /restore ──→ Restore Lambda ──→ 새 EBS 볼륨 생성
```

## 구성 파일
```
project3-smart-vault/
├── main.tf               # 전체 인프라
├── iam.tf                # Lambda별 최소 권한
├── variables.tf
├── outputs.tf            # 테스트 명령어 포함
└── lambda/
    ├── backup/index.py   # backup:true 태그 인스턴스 → 스냅샷 생성
    ├── cleanup/index.py  # RetainUntil 기준 만료 스냅샷 삭제
    └── restore/index.py  # 스냅샷 → 새 EBS 볼륨 복구
```

## 예상 비용
| 서비스 | 무료 범위 | 초과 비용 |
|--------|-----------|----------|
| Lambda | 100만 건/월 | 없음 |
| EventBridge | 무제한 스케줄 | 없음 |
| S3 아카이브 | 5GB | 없음 |
| EBS 스냅샷 | 없음 (GB당 과금) | **$0.05/GB/월** |
| 크로스 리전 복제 | 없음 | **$0.02/GB** |
| SNS | 1,000건 무료 | 없음 |

> ⚠️ **EBS 스냅샷이 유일한 유료 항목** — 테스트용 소규모 볼륨 기준 $1 미만.
> 테스트 후 반드시 `terraform destroy` 실행.

---

## 배포 순서

### 1. variables.tf 수정
```hcl
suffix          = "홍길동-20250527"
alert_email     = "your@email.com"
cleanup_dry_run = true   # 처음엔 true로 안전하게 테스트
retention_days  = 7
```

### 2. 배포
```bash
terraform init
terraform plan
terraform apply
```

---

## 테스트 순서

### Step 1. EC2 인스턴스에 backup 태그 추가
```bash
# 본인 EC2 인스턴스 ID로 교체
aws ec2 create-tags \
  --resources i-xxxxxxxxxxxxxxxxx \
  --tags Key=backup,Value=true \
  --region ap-northeast-2
```
> EC2 인스턴스가 없다면: AWS 콘솔 → EC2 → 인스턴스 시작 (t2.micro / Free Tier)

### Step 2. 백업 Lambda 수동 실행
```bash
# outputs의 test_manual_backup 명령어 실행
aws lambda invoke \
  --function-name p3-smart-vault-backup \
  --payload '{"schedule":"manual-test"}' \
  --region ap-northeast-2 \
  /tmp/backup-result.json && cat /tmp/backup-result.json
```

### Step 3. 스냅샷 생성 확인
```bash
# outputs의 check_snapshots 명령어 실행
aws ec2 describe-snapshots \
  --owner-ids self \
  --filters Name=tag:ManagedBy,Values=smart-vault \
  --region ap-northeast-2 \
  --query 'Snapshots[*].{ID:SnapshotId,Name:Tags[?Key==`Name`]|[0].Value,RetainUntil:Tags[?Key==`RetainUntil`]|[0].Value}' \
  --output table
```

### Step 4. 정리 Lambda 테스트 (DRY RUN)
```bash
# cleanup_dry_run = true 상태에서 실행 — 실제 삭제 없이 대상만 출력
aws lambda invoke \
  --function-name p3-smart-vault-cleanup \
  --region ap-northeast-2 \
  /tmp/cleanup-result.json && cat /tmp/cleanup-result.json
```

### Step 5. 복구 API 테스트
```bash
# Step 3에서 확인한 snapshot_id로 교체
curl -X POST [restore_api_endpoint] \
  -H "Content-Type: application/json" \
  -d '{
    "snapshot_id": "snap-xxxxxxxx",
    "volume_type": "gp3",
    "availability_zone": "ap-northeast-2a"
  }'
```

### Step 6. DR 복제 확인
```bash
# 서울 → 싱가포르 복제 확인
aws s3 ls s3://[dr-archive-bucket]/ --recursive --region ap-southeast-1
```

---

## 검증 체크리스트
- [ ] backup:true 태그 EC2에 스냅샷 자동 생성 확인
- [ ] 스냅샷에 RetainUntil / BackupDate 등 태그 부여 확인
- [ ] Cleanup Lambda DRY RUN 결과 확인
- [ ] 복구 API로 새 EBS 볼륨 생성 확인
- [ ] S3 아카이브에 cleanup 로그 저장 확인
- [ ] DR 버킷에 크로스 리전 복제 확인
- [ ] 이메일로 백업 완료 리포트 수신 확인
- [ ] CloudWatch 대시보드 Lambda 호출 그래프 확인

---

## 리소스 삭제
```bash
# S3 버킷 2개 비우기
aws s3 rm s3://[archive-bucket] --recursive
aws s3 rm s3://[dr-archive-bucket] --recursive --region ap-southeast-1

terraform destroy
```

> ⚠️ EBS 스냅샷은 Terraform이 직접 관리하지 않으므로 콘솔에서 수동 삭제 필요:
> EC2 → Snapshots → ManagedBy=smart-vault 필터 → 전체 선택 → 삭제
