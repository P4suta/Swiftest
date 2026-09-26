namespace Swiftest

inductive PathDecision where
  | accepted
  | empty
  | absolute
  | nul
  | parentTraversal
  | selfTraversal
  | emptySegment
deriving DecidableEq, Repr

def classifyPath (path : String) : PathDecision :=
  let segments := path.splitOn "/"
  if path.isEmpty then .empty
  else if path.startsWith "/" then .absolute
  else if path.toList.contains '\x00' then .nul
  else if segments.contains ".." then .parentTraversal
  else if segments.contains "." then .selfTraversal
  else if segments.contains "" then .emptySegment
  else .accepted

theorem acceptedPathHasNoParent
    (path : String)
    (accepted : classifyPath path = .accepted) :
    (path.splitOn "/").contains ".." = false := by
  unfold classifyPath at accepted
  repeat
    split at accepted
    all_goals try simp_all

theorem acceptedPathHasNoSelf
    (path : String)
    (accepted : classifyPath path = .accepted) :
    (path.splitOn "/").contains "." = false := by
  unfold classifyPath at accepted
  repeat
    split at accepted
    all_goals try simp_all

theorem acceptedPathHasNoEmptySegment
    (path : String)
    (accepted : classifyPath path = .accepted) :
    (path.splitOn "/").contains "" = false := by
  unfold classifyPath at accepted
  repeat
    split at accepted
    all_goals try simp_all

theorem acceptedPathIsRelative
    (path : String)
    (accepted : classifyPath path = .accepted) :
    path.startsWith "/" = false := by
  unfold classifyPath at accepted
  repeat
    split at accepted
    all_goals try simp_all

theorem acceptedPathHasNoNul
    (path : String)
    (accepted : classifyPath path = .accepted) :
    path.toList.contains '\x00' = false := by
  unfold classifyPath at accepted
  repeat
    split at accepted
    all_goals try simp_all

def pathDecisionText : PathDecision → String
  | .accepted => "accepted"
  | .empty => "empty"
  | .absolute => "absolute"
  | .nul => "nul"
  | .parentTraversal => "parent-traversal"
  | .selfTraversal => "self-traversal"
  | .emptySegment => "empty-segment"

def pathOracleCases : List (String × String) := [
  ("empty", ""),
  ("absolute", "/a"),
  ("nul", "a\x00b"),
  ("parent", "a/../b"),
  ("self", "a/./b"),
  ("empty-segment", "a//b"),
  ("trailing", "a/"),
  ("relative", "a/b"),
  ("plain", "a")
]

end Swiftest
