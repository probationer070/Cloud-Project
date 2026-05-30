
from dataclasses import dataclass
from datetime import datetime
from typing import Callable, Dict, Tuple, Literal, Optional, List
from typing import Any

@dataclass
class Rule:
  name: str
  handler: Callable[[Dict[str, Any]], Tuple[bool, str, Dict[str, Any]]]
  
@dataclass
class RuleTrace:
  rule: str
  result: Literal["pass", "fail"]
  reason: str = ""
  metadata: Optional[Dict[str, Any]] = None
  impact: Optional[str] = None
  
@dataclass
class ReplayInput:
    snap: dict
    retain_until: str | None
    now: datetime
    
@dataclass
class PolicyResult:
    should_delete: bool
    reason: str
    expire_date: Optional[datetime]
    trace: List[RuleTrace]