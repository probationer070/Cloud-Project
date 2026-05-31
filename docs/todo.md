# P4 Build Plan — 고객 서비스 AI 챗봇

P1~P3의 구성 패턴을 재사용하는 고객 서비스 AI 챗봇. 이 문서는 P4의 전체 설계·빌드 계획이며,
구현 진행 상황은 `project4-ai-chatbot/README.md`와 동기화한다.

> 관련 설계 문서: [P1](design/p1-static-web/design.md) · [P2](design/p2-serverless-pipeline/design.md) · [P3](design/p3-smart-vault/design.md)

---

## 1. 결정: AI 제공자

- **Google Gemini API**(무료/유료 티어)를 사용한다. AWS Bedrock 대신 선택.
- API 키는 **Lambda 환경 변수**(`GEMINI_API_KEY`)에 저장하고 `var.gemini_api_key`에서 주입한다.
- AI 레이어에 한해 **AWS 카드 등록 불필요**. 나머지는 모두 AWS 스택과 통합.
- `variables.tf`의 `ai_provider`를 `"bedrock"`으로 바꾸고 `terraform apply`하면 Bedrock으로 전환 가능.

---

## 2. 전체 아키텍처

```
[브라우저 / 외부 앱·curl]
            │
            ▼
      API Gateway  ──→  Lambda (챗봇 핵심 로직)
                          │  1. 대화 이력 조회 (DynamoDB)
                          │  2. 프롬프트 조립
                          │  3. Gemini API 호출
                          │  4. 응답 검증/라우팅
                          │  5. 대화 이력 저장 (DynamoDB)
                          │
              ┌───────────┴───────────┐
          DynamoDB                 Gemini API
        (대화 이력)              (AI 응답 생성)
              │
              ▼ (상담원 연결 감지 시)
            SNS → 이메일 알림

  모니터링: CloudWatch (응답 시간 / 에러율)
  웹 UI: S3 + CloudFront (P1 재사용)
```

---

## 3. AWS 리소스 및 역할

| 리소스 | 역할 | 무료 범위 |
|--------|------|-----------|
| API Gateway | 웹 UI + 외부 REST 엔드포인트 | 100만 요청/월 |
| Lambda | 챗봇 핵심 로직 전체 | 100만 요청/월 |
| DynamoDB | 세션별 대화 이력 저장 | 25GB |
| Gemini API | AI 응답 생성 | 무료 티어(+ 종량제) |
| S3 | 정적 웹 UI 호스팅 | 무료 |
| CloudFront | 웹 UI CDN | 무료 |
| SNS | 상담원 연결 알림 | 무료 |
| CloudWatch | 응답 시간 / 에러율 모니터링 | 무료 |

> 개발 단계 예상 비용: Gemini 무료 티어 기준 **약 $0**.

---

## 4. Lambda 내부 로직 (5단계)

### Step 1. 대화 이력 조회
- `session_id`로 DynamoDB에서 이전 메시지 조회.
- 세션이 없으면 새 세션 시작.
- 세션이 있으면 컨텍스트 윈도 관리를 위해 **최근 10턴**만 로드.

### Step 2. 프롬프트 조립
- **System Prompt(고정)**: 회사의 고객 서비스 담당자로 행동, 친근하고 전문적인 톤,
  모르는 것은 솔직하게 인정, 욕설/공격적 언어는 정중히 거절, 해결 불가 시 상담원 연결 안내.
- 현재 사용자 메시지 앞에 대화 이력을 동적으로 추가.

### Step 3. Gemini API 호출
- 조립한 프롬프트를 Gemini에 전송하고 생성된 응답 수신.

### Step 4. 응답 검증 및 라우팅
- 정상 응답: 그대로 반환.
- 상담원 요청: **SNS 알림 발송** + "지금 연결해 드리겠습니다" 메시지 반환(`escalated: true`).
- 공격적 콘텐츠: 경고 메시지로 대체.
- 빈 응답: 기본 fallback 메시지 반환.

### Step 5. 대화 이력 저장
- 현재 턴을 `session_id`, `timestamp`, `role`, `content` 필드로 DynamoDB에 저장.
- **TTL 24시간** 설정 — 자동 만료로 비용 관리.

---

## 5. DynamoDB 테이블 구조

- **테이블명:** `p4-chatbot-sessions`
- **파티션 키:** `session_id` (String) — 브라우저/사용자별 고유
- **정렬 키:** `timestamp` (String) — 대화 순서 정렬
- **추가 필드:**
  - `role` — `user` 또는 `assistant`
  - `content` — 메시지 텍스트
  - `ttl` — Unix timestamp, 24시간 후 자동 삭제

(빌링: `PAY_PER_REQUEST` + TTL 자동 만료 — P2 DynamoDB 패턴 재사용.)

---

## 6. 웹 UI

P1의 기존 S3 + CloudFront 구성에 호스팅한다.

- 사용자 입력 + AI 응답 표시 채팅 창
- 브라우저 `localStorage`에 저장되는 자동 생성 세션 ID
- 대화 이력 표시
- 상담원 연결 버튼
- 로딩 인디케이터

---

## 7. 이전 프로젝트 연계

- **P1 (S3 + CloudFront):** 챗봇 웹 UI 호스팅에 재사용.
- **P2 (DynamoDB 패턴):** 대화 이력 저장 구조(`PAY_PER_REQUEST` + TTL)에 재사용.
- **P3 (SNS 패턴):** 상담원 연결 이메일 알림에 재사용.

---

## 8. 배포 및 테스트 순서

1. `terraform apply`로 인프라 프로비저닝.
2. 웹 UI를 S3에 업로드(`aws s3 sync`) 후 브라우저에서 채팅 테스트.
3. `curl`로 REST 엔드포인트 직접 호출 테스트.
4. 상담원 연결을 트리거하고 SNS 이메일 수신 확인.
5. DynamoDB에서 대화 이력 저장 확인.
6. CloudWatch 대시보드에서 응답 시간/에러율 확인.

### 검증 체크리스트
- [ ] curl 기본 대화 응답 확인
- [ ] 같은 `session_id` 연속 호출 시 이전 대화 기억 확인
- [ ] "상담원 연결" 요청 시 `escalated: true` + 이메일 알림 수신
- [ ] DynamoDB(`p4-chatbot-sessions`)에 대화 이력 저장 확인
- [ ] 브라우저 웹 UI 채팅 동작 확인
- [ ] CloudWatch 대시보드 호출 수 / 응답 시간 그래프 확인
