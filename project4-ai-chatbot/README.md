# Project 4: 고객 서비스 AI 챗봇

## 아키텍처
```
[웹 UI]                  [REST API]
 브라우저                  curl / 외부 앱
    │                          │
    └──────────┬───────────────┘
               ▼
        API Gateway (HTTP)
               ▼
        Lambda (챗봇 로직)
        ┌──────────────────────────┐
        │ 1. 대화 이력 조회         │
        │ 2. System Prompt 조립     │
        │ 3. AI 호출 (Gemini/Bedrock)│
        │ 4. 응답 검증/라우팅       │
        │ 5. 대화 이력 저장         │
        └──────────────────────────┘
             │              │
        DynamoDB         Gemini API
        (대화 이력)       or Bedrock
             │
             ▼ (상담원 연결 시)
           SNS → 이메일
```

## AI 제공자 전환 방법
```
현재: Gemini 2.5 Flash-Lite (무료)
전환: variables.tf에서 ai_provider = "bedrock" 변경 후 terraform apply
```

---

## 배포 순서

### Step 1. Gemini API 키 발급
```
https://aistudio.google.com/apikey
  → "Create API Key" 클릭
  → 키 복사
```

### Step 2. variables.tf 수정
```hcl
suffix         = "홍길동-20250527"   # ← 변경
alert_email    = "your@email.com"    # ← 변경
gemini_api_key = "AIzaSy..."         # ← Gemini API 키 입력
company_name   = "내 쇼핑몰"         # ← 원하는 이름
```

### Step 3. 배포
```bash
terraform init
terraform plan
terraform apply
```

### Step 4. 웹 UI API 엔드포인트 설정
```bash
# terraform apply 완료 후 출력되는 chat_api_endpoint 복사
# website/index.html 열어서 아래 라인 수정:
const API_ENDPOINT = "https://xxxxx.execute-api.ap-northeast-2.amazonaws.com/v1/chat";
```

### Step 5. 웹 UI S3 업로드
```bash
# outputs의 ui_upload_command 실행
aws s3 sync ./website/ s3://[bucket-name]/ --delete

# CloudFront 캐시 무효화
aws cloudfront create-invalidation --distribution-id [id] --paths '/*'
```

### Step 6. 브라우저 접속
```
outputs의 chatbot_ui_url 접속
예: https://d1234abcd.cloudfront.net
```

---

## 테스트 시나리오

### 1. 기본 대화
```bash
curl -X POST [chat_api_endpoint] \
  -H "Content-Type: application/json" \
  -d '{"message": "반품은 어떻게 하나요?", "session_id": "test-001"}'
```

### 2. 대화 이력 연속성 확인
```bash
# 같은 session_id로 2번 연속 호출
# 2번째 메시지에서 1번째 내용을 기억하는지 확인
curl ... -d '{"message": "주문번호는 12345입니다", "session_id": "test-003"}'
curl ... -d '{"message": "아까 말한 주문 배송 조회해주세요", "session_id": "test-003"}'
```

### 3. 상담원 연결 트리거
```bash
curl ... -d '{"message": "상담원 연결해주세요", "session_id": "test-002"}'
# → 응답에 escalated: true
# → 이메일로 알림 수신 확인
```

### 4. DynamoDB 대화 이력 확인
```bash
# outputs의 check_session_history 명령어 실행
aws dynamodb query --table-name p4-chatbot-sessions \
  --key-condition-expression 'session_id = :sid' \
  --expression-attribute-values '{":sid":{"S":"test-003"}}' \
  --region ap-northeast-2
```

---

## Bedrock으로 전환 (카드 등록 후)
```hcl
# variables.tf 수정
ai_provider = "bedrock"

# terraform apply 재실행
terraform apply
```
비용: 테스트 규모 기준 $1~3

---

## 검증 체크리스트
- [ ] curl로 기본 대화 응답 확인
- [ ] 같은 session_id 연속 호출 시 이전 대화 기억 확인
- [ ] "상담원 연결" 요청 시 escalated: true + 이메일 알림 수신
- [ ] DynamoDB에 대화 이력 저장 확인
- [ ] 브라우저에서 웹 UI 채팅 동작 확인
- [ ] CloudWatch 대시보드 호출 수 / 응답 시간 그래프 확인

---

## 리소스 삭제
```bash
aws s3 rm s3://[ui-bucket] --recursive
terraform destroy
```
