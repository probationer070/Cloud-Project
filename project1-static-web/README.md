# Project 1: 보안/성능 최적화 정적 웹사이트

## 아키텍처
```
사용자 → CloudFront (WAF) → S3 (비공개)
                ↓
         CloudWatch 알람 → SNS → 이메일
```

## 구성 리소스
| 리소스 | 역할 | Free Tier |
|--------|------|-----------|
| S3 | 정적 파일 저장 | 5GB / 20,000 GET 무료 |
| CloudFront | 글로벌 CDN + HTTPS | 1TB 전송 무료 |
| WAF | SQL인젝션/XSS/봇 차단 | ⚠️ $5/월 (Web ACL) |
| ACM | SSL 인증서 | 무료 |
| CloudWatch | 모니터링 + 알람 | 10개 알람 무료 |
| SNS | 이메일 알림 | 1,000건 무료 |

**예상 비용: WAF $5~6/월** (나머지는 Free Tier)

---

## 시작 전 준비

### 1. variables.tf 수정 (필수)
```hcl
# 아래 두 값을 반드시 본인 것으로 변경
bucket_name = "p1-static-web-홍길동-20250527"  # 전 세계 고유한 이름
alert_email = "your@email.com"
```

### 2. AWS CLI 인증 확인
```bash
aws sts get-caller-identity
# 본인 계정 ID가 출력되면 OK
```

---

## 배포 순서

### Step 1. Terraform 초기화
```bash
cd project1-static-web
terraform init
```

### Step 2. 배포 미리보기
```bash
terraform plan
# 생성될 리소스 목록 확인 (약 15개)
```

### Step 3. 배포 실행
```bash
terraform apply
# "yes" 입력
# ⏱️ 약 5~10분 소요 (CloudFront 배포가 가장 오래 걸림)
```

### Step 4. 정적 파일 업로드
```bash
# apply 완료 후 출력된 upload_command 복사해서 실행
aws s3 sync ./website/ s3://[버킷이름]/ --delete
```

### Step 5. 접속 확인
```bash
# apply 완료 후 출력된 cloudfront_domain으로 브라우저 접속
# 예: https://d1234abcd.cloudfront.net
```

### Step 6. SNS 이메일 구독 확인
- apply 직후 alert_email로 "AWS Notification - Subscription Confirmation" 메일 수신
- **메일 내 "Confirm subscription" 클릭 필수** (안 하면 알람 이메일 안 옴)

---

## 검증 체크리스트
- [ ] CloudFront URL로 https 접속 성공
- [ ] http 접속 시 https로 자동 리다이렉트 확인
- [ ] S3 직접 URL 접속 시 AccessDenied 확인 (보안 정상)
- [ ] SNS 구독 이메일 확인
- [ ] CloudWatch 대시보드에서 요청 수 확인

---

## 리소스 삭제 (테스트 완료 후)
```bash
# S3 버킷 비우기 (파일 있으면 destroy 실패)
aws s3 rm s3://[버킷이름] --recursive

# 전체 삭제
terraform destroy
# "yes" 입력
```

> ⚠️ WAF는 삭제까지 몇 분 걸릴 수 있음. 에러 시 재시도.

---

## 자주 발생하는 오류

### S3 bucket name already exists
→ `bucket_name` 을 더 고유하게 변경

### WAF rule 오류 (AWSManagedRulesManagedRuleSet)
→ main.tf에서 규칙 2 (AWSManagedRulesAmazonIpReputationList) 블록 주석 처리 후 재시도
→ 실제 규칙명: `AWSManagedRulesAmazonIpReputationList`

### CloudFront 배포 후 403 에러
→ S3 파일 업로드 확인
→ 캐시 무효화: `aws cloudfront create-invalidation --distribution-id [ID] --paths '/*'`
