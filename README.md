# Cloud Project — AWS 실습 포트폴리오 (P1–P4)

Terraform으로 프로비저닝하는 4개의 AWS 프로젝트. 각 프로젝트는 독립 배포 가능하며,
**P4(AI 챗봇)** 는 P1~P3의 패턴을 재사용하는 플래그십 프로젝트입니다.

> **개발 환경 설정** → [`CONTRIBUTING.md`](CONTRIBUTING.md) — 로컬 초기화(`init-all.ps1` / `init-all.sh`), AWS 자격증명, CI 워크플로우

---

## P1 — 보안/성능 최적화 정적 웹사이트

**목적:** S3를 비공개로 유지하고 CloudFront + WAF를 통해서만 콘텐츠를 제공하는 HTTPS 전용 정적 호스팅.

```
사용자 요청
    → WAF (SQLi·XSS 차단, IP 평판 필터, 2000req/5min 속도 제한)
    → CloudFront (HTTPS 강제, 캐시 TTL 1h, 404/403→index.html)
    → S3 (비공개 버킷, OAC 경유만 허용)
         ↓
    CloudWatch 알람 (4xx>5%, 5xx>1%, WAF차단>100/5min)
         → SNS → 이메일
```

| AWS 서비스 | 역할 | 동작 시점 |
|-----------|------|-----------|
| S3 | 정적 파일 저장 (비공개) | CloudFront OAC 요청 시에만 접근 허용 |
| CloudFront | CDN · HTTPS 강제 · SPA 라우팅 | 모든 사용자 요청 |
| WAF (us-east-1) | SQLi·XSS 차단, IP 평판, 속도 제한 | CloudFront 요청 도달 전 |
| CloudWatch | 에러율·WAF 차단 수 모니터링 | 5분 집계 주기, 임계값 초과 시 알람 |
| SNS (서울 + us-east-1) | 알람 이메일 발송 | CloudWatch 알람 상태 전환 시 |

📄 [설계 문서](docs/design/p1-static-web/design.md) · [파일 구조](project1-static-web/file-structure.md)

---

## P2 — 복합 데이터 처리 서버리스 파이프라인

**목적:** CSV·JSON·PDF·이미지 파일을 S3에 업로드하면 자동으로 분류→파싱→추출→저장까지 이어지는 이벤트 드리븐 파이프라인.

```
파일 업로드 (S3 ObjectCreated  또는  POST /upload)
    → Router Lambda (파일 확장자로 경로 결정)
         ├─ csv/json  → SQS 정형 큐  → Parser Lambda   → DynamoDB
         ├─ pdf/image → SQS 비정형 큐 → Extractor Lambda → S3 processed
         └─ 미지원    → S3 quarantine
    (실패 3회 → DLQ → CloudWatch 알람 → SNS → 이메일)
```

| AWS 서비스 | 역할 | 동작 시점 |
|-----------|------|-----------|
| S3 ingestion | 업로드 수신 | ObjectCreated → Router Lambda 트리거 |
| S3 processed | Textract·Rekognition 결과 저장 (90일 후 자동 삭제) | Extractor Lambda 완료 시 |
| S3 quarantine | 미지원/실패 파일 격리 | Router·Parser·Extractor 오류 시 |
| SQS 정형 큐 + DLQ | CSV·JSON 버퍼링, 3회 실패→DLQ | Router가 메시지 전송 시 |
| SQS 비정형 큐 + DLQ | PDF·이미지 버퍼링 | Router가 메시지 전송 시 |
| Lambda Router | 파일 확장자 감지 → 큐 전송 또는 quarantine | S3 ObjectCreated 이벤트 |
| Lambda Parser | CSV/JSON 유효성 검사 → DynamoDB 저장 | SQS 정형 큐 (배치 10) |
| Lambda Extractor | Textract(PDF)·Rekognition(이미지) → S3 저장 | SQS 비정형 큐 (배치 5) |
| DynamoDB | 파싱 결과 레코드 저장 (`PAY_PER_REQUEST`, TTL) | Parser·Extractor 완료 시 |
| API Gateway (HTTP v2) | 외부 파일 수신 엔드포인트 `POST /upload` | 외부 클라이언트 호출 시 |
| CloudWatch | Lambda 에러, DLQ 적재 수 모니터링 | 5분 집계, 임계값 초과 시 알람 |
| SNS | 처리 실패 알림 이메일 | CloudWatch 알람 또는 Lambda 오류 시 |

📄 [설계 문서](docs/design/p2-serverless-pipeline/design.md) · [파일 구조](project2-serverless-pipeline/file-structure.md)

---

## P3 — 지능형 자동 백업 (Smart Vault)

**목적:** `backup:true` 태그가 붙은 EC2의 EBS를 자동 스냅샷·보관 기간 관리·복구하는 완전 자동화 백업 시스템. 싱가포르 DR 복제 포함.

```
EventBridge 매시간/매일 자정 → Backup Lambda
    → backup:true 태그 EC2 탐색
    → EBS 스냅샷 생성 + RetainUntil 태그 부여
    → SNS 리포트 이메일

EventBridge 매일 KST 02:00  → Cleanup Lambda
    → 만료 스냅샷 삭제 (DRY_RUN 모드 지원)
    → S3 아카이브(서울) 로그 저장
         → S3 DR(싱가포르) 크로스리전 복제

API Gateway POST /restore (API 키 인증) → Restore Lambda
    → 스냅샷 → 새 EBS 볼륨 생성

CloudWatch 알람 → SNS → 이메일
```

| AWS 서비스 | 역할 | 동작 시점 |
|-----------|------|-----------|
| EventBridge (매시간) | Backup Lambda 주기 실행 | `rate(1 hour)` |
| EventBridge (매일) | Backup Lambda 일별 실행 | `cron(1 0 * * ?)` UTC = KST 09:01 |
| EventBridge (정리) | Cleanup Lambda 실행 | `cron(0 17 * * ?)` UTC = KST 02:00 |
| Lambda Backup | EC2 탐색 → EBS 스냅샷 생성 | EventBridge 스케줄 |
| Lambda Cleanup | 만료 스냅샷 삭제 + 로그 기록 | EventBridge 스케줄 (DRY_RUN 기본값 true) |
| Lambda Restore | 스냅샷 → 새 EBS 볼륨 | `POST /restore` API 호출 시 |
| EBS 스냅샷 | 증분 백업 데이터 | Backup이 생성, Cleanup이 만료 삭제, Restore가 활용 |
| S3 아카이브 (서울) | Cleanup 로그 저장 | Cleanup Lambda 완료 시 |
| S3 DR (싱가포르) | 크로스리전 재해 복구 복제본 | S3 복제 규칙 (`cleanup-logs/*`, STANDARD_IA) |
| API Gateway (REST v1) | `POST /restore` — API 키 인증 필수 | 수동 복구 요청 시 |
| CloudWatch | Lambda 에러, 백업 미실행, 실행 시간 초과 모니터링 | 임계값 초과 또는 6시간 내 미호출 시 |
| SNS | 백업 리포트·에러 알림 이메일 | Lambda 실행 결과 및 CloudWatch 알람 시 |

📄 [설계 문서](docs/design/p3-smart-vault/design.md) · [파일 구조](project3-smart-vault/file-structure.md)

---

## P4 — 고객 서비스 AI 챗봇 ★ 플래그십

**목적:** Gemini API 기반 고객 서비스 챗봇. API Gateway + Lambda 5단계 처리, DynamoDB 대화 이력(24h TTL), 상담원 연결 시 SNS 알림. P1·P2·P3 패턴 재사용.

```
브라우저 / curl
    → API Gateway (POST /chat)
    → Lambda chatbot
         ├─ 1. DynamoDB 대화 이력 조회 (최근 10턴)
         ├─ 2. 프롬프트 조립 (System Prompt + 이력 + 현재 메시지)
         ├─ 3. Gemini API 호출 (키: SSM Parameter Store에서 Cold Start 시 1회 조회)
         ├─ 4. 응답 검증/라우팅 (정상·에스컬레이션·욕설·fallback)
         └─ 5. DynamoDB 대화 이력 저장 (TTL 24h)
              ↓ (에스컬레이션 감지 시)
            SNS → 이메일 알림

웹 UI: CloudFront → S3 (P1 패턴 재사용)
CloudWatch 알람 (에러·응답지연 10초 초과) → SNS → 이메일
```

| AWS 서비스 | 역할 | 동작 시점 |
|-----------|------|-----------|
| API Gateway (HTTP v2) | `POST /chat` REST 엔드포인트 | 사용자 메시지 전송 시 |
| Lambda chatbot | 5단계 챗봇 핵심 로직 | API Gateway 호출 시 (timeout 45s, ARM64) |
| DynamoDB `p4-chatbot-sessions` | 세션별 대화 이력 저장 (TTL 24h 자동 만료) | Lambda 매 호출마다 읽기·쓰기 |
| SSM Parameter Store | Gemini API 키 보관 (SecureString, KMS 암호화) | Lambda Cold Start 시 1회 조회 후 컨테이너 수명 동안 캐시 |
| Gemini API (외부) | AI 응답 생성 (HTTP timeout 25s) | Lambda 매 호출마다 |
| SNS | 상담원 연결 요청 이메일 알림 | 응답에 ESCALATE 감지 시 |
| S3 | 웹 UI 정적 파일 호스팅 (비공개, OAC) | CloudFront 요청 시 |
| CloudFront | 웹 UI HTTPS 제공, CORS Origin 소스 | 브라우저 접속 시 |
| CloudWatch | Lambda 에러 수·응답 시간 모니터링 | 5분 집계, 임계값 초과 시 알람 |

**P1~P3 재사용 패턴:**
- **P1 →** S3 + CloudFront(OAC) 웹 UI 호스팅
- **P2 →** DynamoDB `PAY_PER_REQUEST` + TTL 자동 만료
- **P3 →** SNS 이메일 알림 (에스컬레이션)

📄 [P4 전체 빌드 계획](docs/todo.md) · [파일 구조](project4-ai-chatbot/file-structure.md) · [ADR: SSM 자격증명](docs/adr/0001-ssm-parameter-store-for-api-credentials.md)

---

## 저장소 구조

```
Cloud Project/
├── project1-static-web/          # P1 인프라 + 웹사이트
├── project2-serverless-pipeline/ # P2 인프라 + Lambda
├── project3-smart-vault/         # P3 인프라 + Lambda
├── project4-ai-chatbot/          # P4 인프라 + Lambda + 웹 UI
├── docs/
│   ├── design/                   # P1·P2·P3 설계 문서
│   ├── adr/                      # Architecture Decision Records
│   ├── todo.md                   # P4 전체 빌드 계획
│   ├── changelog/                # 변경 로그 (모든 코드 변경 기록)
│   ├── error/                    # 버그 기록
│   └── refactoring-*.md          # 리팩터링 참고 문서
├── .agents/                      # 서브에이전트 명세 (refactoring · idea-management · security)
└── 정리자료/                     # 블로그용 수기 노트 (수정 금지)
```

## 공통 워크플로

1. 변경 유형 확인 → [`.agents/README.md`](.agents/README.md) 결정 매트릭스에서 에이전트 선택
2. 코딩·인프라 가이드라인 → [`.claude/CLAUDE.md`](.claude/CLAUDE.md)
3. 모든 코드 변경 → `docs/changelog/` 기록 필수
4. 확인된 버그 → `docs/error/` 기록 필수

## 배포 (공통)

각 프로젝트 디렉터리에서:

```bash
terraform init
terraform plan
terraform apply
# 테스트 후
terraform destroy
```

세부 배포·테스트 절차는 각 프로젝트 디렉터리의 `README.md`와 `file-structure.md`를 참고하세요.
