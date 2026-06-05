# P4 Design — AI 챗봇 (고객 서비스 AI Chatbot)

**Directory:** `project4-ai-chatbot/`
**Stack:** API Gateway (HTTP v2) + Lambda + DynamoDB + SSM + SNS + S3 + CloudFront + CloudWatch
**Region:** `ap-northeast-2` (Seoul)

## Purpose

Gemini API 기반 고객 서비스 챗봇. REST API 엔드포인트로 메시지를 받아 DynamoDB에 대화 이력을
유지하며 AI 응답을 반환한다. 상담원 연결이 필요한 경우 SNS로 이메일 알림을 발송하고,
웹 UI는 S3 + CloudFront로 제공된다.

> **프로젝트 독립성:** P4는 P1·P2·P3의 배포 인프라를 참조하지 않는다. 필요한 모든
> AWS 리소스(S3·CloudFront·DynamoDB·SNS·API Gateway)를 자체 Terraform으로 생성하므로,
> P1~P3 없이도 단독 배포·테스트가 가능하다.

## Architecture

```
브라우저 / curl
    → CloudFront (HTTPS) ─ OAC ─▶ S3 (웹 UI, 비공개)
    → API Gateway HTTP v2 (POST /chat)
         ▼
    Lambda chatbot (ARM64, 256MB, timeout 45s)
    ┌─────────────────────────────────────────────┐
    │ 1. get_history   DynamoDB Query (최근 10턴)  │
    │ 2. build_prompt  System Prompt + 이력 조립   │
    │ 3. call_ai       Gemini API (HTTP 25s)       │
    │                  or Bedrock InvokeModel      │
    │ 4. route         ESCALATE / 욕설 / fallback  │
    │ 5. save_history  DynamoDB BatchWriter        │
    └─────────────────────────────────────────────┘
         │                     │
    DynamoDB               SSM Parameter Store
    (sessions, TTL 24h)    (Gemini key, Cold Start 1회 조회)
         │
         ▼ (ESCALATE 감지 시)
       SNS → 이메일

CloudWatch 알람 (에러 수 > 5, 응답 시간 > 10s) → SNS → 이메일
```

## Resource Inventory

| Resource | Detail | Source |
|----------|--------|--------|
| DynamoDB `p4-chatbot-sessions` | PK `session_id` (S), SK `timestamp` (S), `PAY_PER_REQUEST`, TTL 24h | `main.tf:29-52` |
| SNS `p4-chatbot-alerts` | 이메일 구독 (에스컬레이션 + CloudWatch 알람) | `main.tf:58-67` |
| Lambda `p4-chatbot-chatbot` | ARM64, 256MB, timeout 45s, Python 3.12 | `main.tf:79-110` |
| API Gateway HTTP v2 | `POST /chat`, CORS `allow_origins = ["*"]` | `main.tf:123-187` |
| S3 `p4-chatbot-ui-{suffix}` | 웹 UI 파일, 비공개, AES256 SSE | `main.tf:195-214` |
| CloudFront OAC | sigv4, `signing_behavior = always` | `main.tf:216-221` |
| CloudFront distribution | HTTPS 전용, `default_root_object = index.html`, 404→index.html | `main.tf:223-267` |
| SSM Parameter Store | `/cloud-portfolio/gemini-api-key` (SecureString, KMS 암호화) | 수동 생성 (Terraform 외부) |
| CloudWatch alarms | Lambda 에러 > 5/5min, 응답 시간 > 10s | `main.tf:292-322` |
| CloudWatch dashboard | 호출 수, 응답 시간, 에러 수 | `main.tf:324-358` |

## Lambda 5-Step Flow

| Step | 함수 | 동작 |
|------|------|------|
| 1 | `get_history` | DynamoDB Query — `session_id` 기준 최근 10턴 조회 |
| 2 | `build_prompt` | System Prompt + 대화 이력 + 현재 메시지 조립 |
| 3 | `call_gemini` / `call_bedrock` | AI API 호출 (HTTP timeout 25s / Bedrock boto3) |
| 4 | `route_response` | `ESCALATE` 키워드 감지 → SNS 발행; 욕설 감지 → 경고 응답; timeout → fallback |
| 5 | `save_history` | DynamoDB BatchWriter — 사용자/어시스턴트 메시지 저장, TTL = now + 24h |

## DynamoDB 대화 이력 설계

DynamoDB 테이블 `p4-chatbot-sessions`의 키 설계와 타임스탬프 규칙.

### 키 구조

| 속성 | 타입 | 역할 |
|------|------|------|
| `session_id` | S (PK) | 세션 식별자. 프론트엔드가 생성(`"web-" + random()`) |
| `timestamp` | S (SK) | ISO 8601 + 순서 suffix. 오름차순 정렬로 대화 순서 보장 |
| `role` | S | `"user"` 또는 `"assistant"` |
| `content` | S | 메시지 본문 |
| `ttl` | N | Unix epoch. DynamoDB TTL이 24h 후 자동 삭제 |

### 타임스탬프 Suffix 규칙 — `_0` (user) / `_1` (assistant)

`save_history()`는 한 턴(user + assistant)을 같은 ISO 타임스탬프에 suffix로 구분하여 저장한다:

```
2026-06-05T14:23:45.123456+00:00_0   →  role: "user"
2026-06-05T14:23:45.123456+00:00_1   →  role: "assistant"
```

**왜 `_0` / `_1`인가?**

DynamoDB는 SK를 문자열 오름차순으로 정렬한다. 같은 ISO 타임스탬프에 두 메시지가
저장될 때, `'0' < '1'`이므로 user 메시지가 항상 assistant 메시지보다 앞에 온다.

이전 구현은 `_user` / `_assistant`를 사용했는데, `'a' < 'u'`이므로 assistant가 user보다
먼저 정렬되었다. `get_history()`의 페어링 루프는 `[user, assistant]` 순서를 전제하므로,
잘못된 순서로 조회된 아이템은 모두 페어링에 실패하고 대화 이력이 유실되었다. 3턴 이상의
대화에서는 이전 턴의 user 메시지와 다음 턴의 assistant 메시지가 교차 매칭되어 엉뚱한
컨텍스트가 AI에 전달되는 반복 응답 버그가 발생했다 (changelog `26-06-05` 참조).

### get_history() 페어링 로직

```python
# ScanIndexForward=True → SK 오름차순 = [user_T1, asst_T1, user_T2, asst_T2, ...]
items = table.query(KeyConditionExpression=Key("session_id").eq(session_id),
                    ScanIndexForward=True, Limit=MAX_HISTORY_TURNS * 2)
# [user, assistant] 쌍으로 묶기
while i + 1 < len(items):
    if items[i]["role"] == "user" and items[i+1]["role"] == "assistant":
        history.append({"user": items[i]["content"], "assistant": items[i+1]["content"]})
        i += 2
    else:
        i += 1  # 비정상 아이템 건너뜀
```

`_0` < `_1` suffix가 이 로직의 전제 조건이다. suffix를 바꿀 때는 이 순서 불변식을 반드시 유지해야 한다.

## Security Notes

- Gemini API 키는 환경변수 아님 — SSM SecureString (KMS 암호화), Cold Start 시 1회 조회 후 컨테이너 캐시.
- Lambda IAM 역할은 최소 권한: 해당 DynamoDB 테이블·SNS 토픽·SSM 파라미터 ARN에만 허용.
- CloudFront `ALLOWED_ORIGIN` 환경변수로 Lambda CORS 응답 헤더 고정 (wildcard `*` 사용 안 함).
- API Gateway CORS는 `allow_origins = ["*"]`로 설정 — 프로덕션 시 CloudFront 도메인으로 제한 필요.
- `force_destroy = true`는 dev 편의용 — 프로덕션에서 제거.

## Cost

| 서비스 | 무료 범위 | 초과 비용 |
|--------|-----------|----------|
| Lambda | 100만 건/월 | 없음 (테스트 규모) |
| API Gateway | 100만 건/월 | 없음 |
| DynamoDB | 25GB / 200만 r·w | 없음 |
| SSM Parameter Store | 표준 10,000개 | 없음 |
| S3 + CloudFront | 5GB / 1TB | 없음 |
| Gemini API (Gemma 4 26B) | 무료 티어 1,500 req/day | 없음 (1.5k RPD 이내) |
| SNS | 1,000건 무료 | 없음 |

실질적으로 $0/mo. Bedrock 전환 시 $1~3/mo.

## AI Provider Switching

`variables.tf`에서 `ai_provider` 및 `gemini_model` 값 변경 후 `terraform apply`:

```hcl
ai_provider  = "gemini"            # 기본값
gemini_model = "gemma-4-26b-a4b-it" # 현재 모델: Gemma 4 26B (무료, 1,500 req/day)
# gemini_model = "gemini-2.0-flash" # 구 모델 (분당 제한 없음, 분당 요청 수 제한 있음)

ai_provider = "bedrock"            # Claude 3 Haiku (카드 등록 필요, us-east-1)
```

코드 변경 없이 환경변수(`GEMINI_MODEL`)만으로 Gemini 계열 모델을 전환할 수 있다.
Gemma 모델은 동일한 `call_gemini()` 함수와 `v1beta` 엔드포인트를 사용한다.

## Deployment Sequence

전체 배포 절차는 [`README.md`](../../project4-ai-chatbot/README.md) 참조.

요약:
1. Gemini API 키 발급 (Google AI Studio)
2. SSM에 키 저장 (`aws ssm put-parameter --name /cloud-portfolio/gemini-api-key ...`)
3. `variables.tf` 수정 (suffix, alert_email)
4. `terraform init && terraform apply`
5. `website/index.html`에 `chat_api_endpoint` 입력
6. `aws s3 sync` + CloudFront 캐시 무효화
7. 브라우저 접속 및 curl 테스트

## Pattern Reuse from P1–P3

P4가 코드 패턴으로 참고한 선행 프로젝트. **배포 인프라 의존 없음** — P4 main.tf가 모든 리소스를 직접 생성한다.

| 패턴 출처 | 차용 내용 | P4 적용 위치 |
|-----------|-----------|-------------|
| P1 (Static Web) | S3 비공개 + CloudFront OAC + HTTPS 전용 | `main.tf:195-286` 웹 UI 호스팅 |
| P2 (Pipeline) | DynamoDB `PAY_PER_REQUEST` + TTL 자동 만료 | `main.tf:29-52` sessions 테이블 |
| P3 (Smart Vault) | SNS 이메일 알림 토픽/구독 패턴 | `main.tf:58-67` alerts 토픽 |
