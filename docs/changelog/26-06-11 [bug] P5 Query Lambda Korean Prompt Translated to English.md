# 26-06-11 [bug] P5 Query Lambda Korean Prompt Translated to English

**Type:** bug
**Branch / Commit:** Testo / —

## Files Changed

| File | Function / Class | What Changed |
|------|-----------------|--------------|
| `project5-document-engine/lambda/query/index.py` | `generate_answer` | Translated RAG prompt from Korean to English |

## Why Changed

The `generate_answer` prompt was written entirely in Korean. Claude followed the Korean instructions and always responded in Korean regardless of the question language. An English question ("What was the Q4 revenue?") returned a Korean answer.

## Contents Diff

**`lambda/query/index.py` — `generate_answer`**
```python
# Before
prompt = f"""당신은 문서 분석 전문가입니다. 아래 제공된 문서 내용만을 근거로 질문에 답변하세요.
[문서 내용] ... [질문] ... [답변 규칙]
- 반드시 위 문서 내용에 근거해서만 답변하세요
- 문서에 없는 내용은 "문서에서 확인할 수 없습니다"라고 하세요
- 답변 마지막에 참고한 출처를 명시하세요
- 간결하고 명확하게 답변하세요"""

# After
prompt = f"""You are a document analysis expert. Answer the question using only the document content provided below.
[Document Content] ... [Question] ... [Answer Rules]
- Base your answer strictly on the document content above
- If the information is not in the document, say "This information is not available in the provided documents"
- Cite the sources you referenced at the end of your answer
- Be concise and clear"""
```

## Improvements

Claude now responds in English, matching the language of the documents and questions.

## Performance Impact

none

## Agents Consulted

none

## Findings Addressed

none

## Findings Deferred

none
