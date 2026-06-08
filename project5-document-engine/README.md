# Project 5: 지능형 문서 분석 엔진 (RAG 기반)

## ⚠️ 비용 경고 — 반드시 읽으세요
```
OpenSearch (t3.small): ~$0.036/시간 → 하루 ~$0.86 → 한 달 방치 시 ~$26
→ 테스트 완료 즉시 terraform destroy 실행 필수!
```

## 아키텍처 (RAG 패턴)
```
[문서 업로드]
  PDF → S3 → Lambda(Ingest)
               ↓ Textract    ↓ 청크 분할
               텍스트 추출   500단어 단위
                    ↓
              Titan 임베딩  (텍스트 → 1536차원 벡터)
                    ↓
              OpenSearch 색인 (벡터 저장)
                    ↓
              DynamoDB 메타데이터 저장

[질문 → 답변]
  질문 → API Gateway → Lambda(Query)
                         ↓
                   Titan 임베딩 (질문 벡터화)
                         ↓
                   OpenSearch kNN 검색 (유사 청크 top-5)
                         ↓
                   Bedrock Claude (청크 기반 답변 생성)
                         ↓
                   답변 + 출처 반환
```

## 구성 파일
```
project5-document-engine/
├── main.tf                  # S3, OpenSearch, DynamoDB, Lambda×2, API GW
├── iam.tf                   # Lambda별 최소 권한
├── variables.tf
├── outputs.tf               # Step-by-Step 테스트 명령어
└── lambda/
    ├── ingest/index.py      # 문서 처리 파이프라인
    └── query/index.py       # 의미 검색 + 답변 생성
└── sample_docs/
    └── create_sample_pdf.py # 테스트용 PDF 생성 스크립트
```

---

## 배포 및 테스트 순서

### Step 0. 사전 준비
```hcl
# variables.tf 수정
suffix      = "홍길동-20250527"
alert_email = "your@email.com"
```

```bash
# Bedrock 모델 액세스 확인 (us-east-1)
# - amazon.titan-embed-text-v2:0
# - anthropic.claude-3-haiku-20240307-v1:0
```

### Step 1. 배포
```bash
terraform init
terraform plan
terraform apply
# OpenSearch 생성에 10~15분 소요 — 기다리세요
```

### Step 2. OpenSearch 인덱스 생성
```bash
# outputs의 step1_create_index 명령어 실행
# knn_vector 필드 매핑 생성 (1536차원)
```

### Step 3. 테스트 PDF 생성 및 업로드
```bash
cd sample_docs
pip install reportlab
python3 create_sample_pdf.py

# S3 업로드 → Ingest Lambda 자동 실행
aws s3 cp sample.pdf s3://[documents-bucket]/sample.pdf

# Lambda 로그 실시간 확인
aws logs tail /aws/lambda/p5-doc-engine-ingest --follow
```

### Step 4. 처리 완료 확인
```bash
# DynamoDB에서 status=completed 확인
aws dynamodb scan --table-name p5-doc-engine-documents

# OpenSearch 색인 건수 확인
# outputs의 step4_check_index 명령어 실행
```

### Step 5. 질의응답 테스트
```bash
# outputs의 step5_query_test 명령어 실행

# 핵심 테스트: 표현이 달라도 같은 내용 검색되는지
curl -X POST [query_api_endpoint] \
  -H "Content-Type: application/json" \
  -d '{"question": "4분기 수익이 얼마인가요?"}'
# → "Q4 Revenue hit 2 mil"과 의미적으로 매칭됨

curl -X POST [query_api_endpoint] \
  -H "Content-Type: application/json" \
  -d '{"question": "클라우드 전환으로 얼마나 절감했나요?"}'
# → AWS 관련 청크 검색 후 Claude가 답변 생성
```

### Step 6. ⚠️ 즉시 삭제 (비용 차단)
```bash
aws s3 rm s3://[documents-bucket] --recursive
terraform destroy

# AWS 콘솔에서 OpenSearch 삭제 완료 확인
# https://ap-northeast-2.console.aws.amazon.com/esv3/home
```

---

## 검증 체크리스트
- [ ] OpenSearch 인덱스 생성 확인 (step1)
- [ ] PDF 업로드 후 Ingest Lambda 자동 실행 확인
- [ ] DynamoDB에 status=completed 저장 확인
- [ ] OpenSearch 색인 건수 > 0 확인
- [ ] 질문 API 호출 시 답변 + 출처 반환 확인
- [ ] 의미 검색 동작 확인 (다른 표현으로 같은 내용 검색)
- [ ] terraform destroy 완료 + AWS 콘솔 OpenSearch 삭제 확인

---

## RAG가 뭔가요? (면접 답변용)

RAG(Retrieval-Augmented Generation)는 AI가 답변할 때
학습 데이터가 아닌 **실제 문서에서 근거를 찾아 답변**하는 패턴입니다.

```
일반 AI: 학습된 지식으로 답변 → 환각(Hallucination) 위험
RAG:     문서 검색 → 근거 기반 답변 → 정확도 높음
```

P5가 이걸 구현한 방식:
1. 문서 → 벡터 변환 (의미를 숫자로)
2. 질문 → 벡터 변환
3. 벡터 유사도로 관련 문단 검색
4. 검색된 문단을 근거로 Claude가 답변
