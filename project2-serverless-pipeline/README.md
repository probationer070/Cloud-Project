# Project 2: 복합 데이터 처리 서버리스 파이프라인

## 아키텍처
```
[파일 업로드]
  정형 (CSV/JSON)  ──┐
  비정형 (PDF/이미지) ──┼──→ S3 Ingestion ──→ Lambda Router
  알 수 없는 형식   ──┘          |                    |
                                 |          ┌─────────┴─────────┐
                                 |     SQS 정형 큐         SQS 비정형 큐
                                 |          |                    |
                                 |    Lambda Parser       Lambda Extractor
                                 |     CSV/JSON 검증       Textract / Rekognition
                                 |          |                    |
                                 |    DynamoDB 저장       S3 Processed 저장
                                 |          |                    |
                                 |          └─────┬──────────────┘
                                 |           오류 시 Quarantine
                                 |                |
                                 └────────── SNS 알림 → 이메일
```

## 구성 파일
```
project2-serverless-pipeline/
├── main.tf               # S3, SQS, DynamoDB, Lambda, API GW, CloudWatch
├── iam.tf                # Lambda 실행 역할 및 권한
├── variables.tf          # 설정값
├── outputs.tf            # 배포 후 확인할 값 + 테스트 명령어
├── lambda/
│   ├── router/index.py   # 파일 유형 감지 및 라우팅
│   ├── parser/index.py   # CSV/JSON 파싱 및 검증
│   └── extractor/index.py # Textract/Rekognition 호출
└── sample_data/
    ├── test.csv          # 정형 테스트 데이터
    └── test.json         # 정형 테스트 데이터 (JSON)
```

## 예상 비용
| 서비스 | Free Tier | 초과 비용 |
|--------|-----------|----------|
| Lambda | 100만 건/월 | 거의 없음 |
| S3 | 5GB / 20,000 GET | 거의 없음 |
| SQS | 100만 건/월 | 없음 |
| DynamoDB | 25GB / 25RCU+WCU | 없음 |
| Textract | 1,000페이지/월 | 초과 시 $1.5/1000페이지 |
| Rekognition | 5,000장/월 | 초과 시 $1/1000장 |

**테스트 규모 기준 예상: $0~1**

---

## 배포 순서

### 1. variables.tf 수정
```hcl
suffix      = "홍길동-20250527"   # 고유한 값으로 변경
alert_email = "your@email.com"
```

### 2. 배포
```bash
terraform init
terraform plan
terraform apply
# SNS 구독 확인 이메일 수신 → "Confirm subscription" 클릭
```

### 3. 테스트 (순서대로)

**① 정형 데이터 (CSV)**
```bash
aws s3 cp sample_data/test.csv s3://[ingestion-bucket]/test.csv
# 약 5~10초 후 DynamoDB 저장 확인:
aws dynamodb scan --table-name p2-pipeline-records --region ap-northeast-2
```

**② 정형 데이터 (JSON)**
```bash
aws s3 cp sample_data/test.json s3://[ingestion-bucket]/test.json
```

**③ Quarantine 테스트 (알 수 없는 형식)**
```bash
echo "test" > sample_data/test.xyz
aws s3 cp sample_data/test.xyz s3://[ingestion-bucket]/test.xyz
# Quarantine 버킷에 이동됐는지 확인:
aws s3 ls s3://[quarantine-bucket]/ --recursive
```

**④ PDF 테스트 (Textract)**
```bash
# PDF 파일 준비 후
aws s3 cp your_file.pdf s3://[ingestion-bucket]/your_file.pdf
# Processed 버킷에 JSON 결과 확인:
aws s3 ls s3://[processed-bucket]/results/ --recursive
```

**⑤ API Gateway 테스트**
```bash
# outputs에서 api_endpoint 확인 후:
curl -X POST [api_endpoint] \
  -H "Content-Type: application/json" \
  -d '{"test": "api gateway 연동 확인"}'
```

### 4. CloudWatch 대시보드 확인
- outputs의 `dashboard_url` 접속
- Lambda 호출 수, 에러 수, SQS 큐 현황 확인

---

## 검증 체크리스트
- [ ] CSV 업로드 → DynamoDB 저장 확인
- [ ] JSON 업로드 → DynamoDB 저장 확인
- [ ] .xyz 업로드 → Quarantine 이동 확인
- [ ] PDF 업로드 → Processed 버킷에 결과 JSON 확인
- [ ] CloudWatch 대시보드 Lambda 호출 수 그래프 확인
- [ ] DLQ가 비어 있는지 확인 (처리 실패 없음)

---

## 리소스 삭제
```bash
# S3 버킷 3개 비우기
aws s3 rm s3://[ingestion-bucket] --recursive
aws s3 rm s3://[processed-bucket] --recursive
aws s3 rm s3://[quarantine-bucket] --recursive

terraform destroy
```

---

## 자주 발생하는 오류

### Lambda 권한 오류 (AccessDenied)
→ `iam.tf` 에서 해당 Lambda의 정책 확인
→ Textract/Rekognition은 `Resource = "*"` 필요

### SQS 트리거 안 됨
→ Lambda event source mapping 상태 확인:
```bash
aws lambda list-event-source-mappings --function-name p2-pipeline-parser
```

### Textract 페이지 수 초과
→ `detect_document_text` 는 단일 페이지만 처리
→ 여러 페이지 PDF는 `start_document_text_detection` (비동기) 사용 필요
