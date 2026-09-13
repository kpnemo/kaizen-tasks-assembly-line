# Graph Report - webapp  (2026-09-13)

## Corpus Check
- 71 files · ~133,289 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 5 file(s) not represented in the graph (top: (none) 5)

## Summary
- 285 nodes · 344 edges · 25 communities (16 shown, 9 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 40 edges (avg confidence: 0.87)
- Token cost: 429,024 input · 0 output

## Community Hubs (Navigation)
- Implement-Issue Skill Flow
- PRD and Product Skills
- Smoke Package Dependencies
- Ship Script Library
- Triage and Readiness Rubric
- Interview Adapter and Pipeline Specs
- Root Package Scripts
- Pipeline Ship Design
- CI/CD and Railway Plans
- TypeScript Config
- Playwright Smoke Tests
- Interview SSE Streaming
- Prettier Config
- Workspace Setup Script
- Accent Color and Theme Toggle
- Label Setup Script
- Docs-Check Stop Hook
- Format File Hook
- Branch Protection Script
- Probe Script
- Codex Companion Runner
- Root Session Orchestration
- Version Check Script
- Seed Requests Script
- Cut Release Script

## God Nodes (most connected - your core abstractions)
1. `implement-issue skill` - 14 edges
2. `compilerOptions` - 9 edges
3. `kaizen-tasks-assembly-line workspace` - 9 edges
4. `Readiness rubric (clarity, complexity, risk)` - 9 edges
5. `auto-implement-issue skill` - 8 edges
6. `triage-requests skill` - 8 edges
7. `ship workflow` - 7 edges
8. `Kaizen Tasks Assembly Line Implementation Plan` - 7 edges
9. `Triage report 2026-09-10` - 7 edges
10. `scripts` - 6 edges

## Surprising Connections (you probably didn't know these)
- `Clarifying questions (clarity below 3)` --semantically_similar_to--> `One bounded round of four questions`  [INFERRED] [semantically similar]
  rubric/readiness.md → .claude/skills/implement-issue/SKILL.md
- `docs-check --ci gate` --semantically_similar_to--> `ci workflow`  [INFERRED] [semantically similar]
  .claude/skills/implement-issue/SKILL.md → .github/workflows/ci.yml
- `Triage comment upsert by marker` --semantically_similar_to--> `Idempotent ship with resume marker`  [INFERRED] [semantically similar]
  .claude/skills/triage-requests/SKILL.md → .github/workflows/ship.yml
- `Spec #34: size the breakdown to the task` --semantically_similar_to--> `Seed request: Make the AI smarter`  [INFERRED] [semantically similar]
  docs/superpowers/specs/2026-09-12-issue-34-size-the-automatic-breakdown-to-the-task.md → seeds/requests/02-smarter-ai.md
- `Seed request: Regenerate suggestions with a hint` --semantically_similar_to--> `Spec #34: size the breakdown to the task`  [INFERRED] [semantically similar]
  seeds/requests/04-regenerate-with-hint.md → docs/superpowers/specs/2026-09-12-issue-34-size-the-automatic-breakdown-to-the-task.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Issue lifecycle from intake to shipped** — _github_issue_template_feature_request_feature_request_form, _claude_skills_seed_requests_skill_seed_requests, _claude_skills_triage_requests_skill_triage_requests, _claude_skills_implement_issue_skill_implement_issue, _github_workflows_ship_ship_workflow, _github_workflows_issue_lifecycle_issue_lifecycle_workflow, _claude_skills_triage_requests_skill_lifecycle_labels [EXTRACTED 1.00]
- **Unattended run: Codex stand-in, prompts, endings** — _claude_skills_auto_implement_issue_skill_auto_implement_issue, _claude_skills_auto_implement_issue_skill_unattended_overrides, _claude_skills_auto_implement_issue_round_prompt_round_prompt, _claude_skills_auto_implement_issue_spec_review_prompt_spec_review_prompt, _claude_skills_auto_implement_issue_skill_codex_companion_runner, _claude_skills_auto_implement_issue_skill_fallback_not_a_stop, _claude_skills_auto_implement_issue_skill_ready_for_staging [EXTRACTED 1.00]
- **Readiness scoring system** — rubric_readiness_readiness_rubric, rubric_readiness_clarity_scale, rubric_readiness_readiness_formula, rubric_readiness_architecture_change_test, rubric_readiness_clarifying_questions [EXTRACTED 1.00]
- **Pipeline control room: API, page, ship workflow and the facilitator's two clicks** — docs_superpowers_plans_2026_09_11_pipeline_api_plan, docs_superpowers_plans_2026_09_11_pipeline_page_plan, docs_superpowers_plans_2026_09_11_pipeline_ship_workflow_plan, docs_playbook_pipeline_control_room, docs_superpowers_plans_2026_09_11_pipeline_api_facilitator_authorization [EXTRACTED 1.00]
- **Request to production flow: intake, triage, implement, promote, ship** — docs_prd_feature_request_interview, docs_prd_triage_requests_skill, docs_prd_implement_issue_skill, docs_prd_promote_workflow, docs_runbook_ship_sequence [INFERRED 0.85]
- **Build lane plans coordinated by the master plan** — docs_superpowers_plans_2026_09_08_master_plan_master_plan, docs_superpowers_plans_2026_09_08_kaizen_tasks_assembly_line_assembly_line_plan, docs_superpowers_plans_2026_09_08_kaizen_tasks_cicd_cicd_plan, docs_cicd_log_cicd_lane_log [EXTRACTED 1.00]
- **One interview turn end to end** — docs_superpowers_specs_2026_09_10_agentic_feature_request_design_interview_model_seam, docs_superpowers_specs_2026_09_10_agentic_feature_request_design_sse_stream_protocol, docs_superpowers_specs_2026_09_10_agentic_feature_request_design_conversation_table, docs_superpowers_specs_2026_09_10_agentic_feature_request_design_conversation_stream_parser, docs_superpowers_specs_2026_09_12_context_aware_interview_design_product_context_loader [EXTRACTED 1.00]
- **Ship to production flow** — docs_superpowers_specs_2026_09_11_pipeline_control_room_design_pipeline_page, docs_superpowers_specs_2026_09_11_pipeline_control_room_design_ship_endpoint, docs_superpowers_specs_2026_09_11_pipeline_control_room_design_ship_workflow, docs_superpowers_specs_2026_09_11_pipeline_control_room_design_ship_marker, docs_superpowers_specs_2026_09_11_pipeline_control_room_design_next_version_rule, docs_superpowers_specs_2026_09_11_pipeline_control_room_design_deploy_passphrase_guard [EXTRACTED 1.00]
- **Consumers of the readiness rubric** — docs_superpowers_specs_2026_09_08_kaizen_tasks_assembly_line_design_readiness_rubric, docs_superpowers_specs_2026_09_08_kaizen_tasks_assembly_line_design_triage_requests_skill, docs_superpowers_specs_2026_09_10_agentic_feature_request_design_vendored_rubric_copy, docs_superpowers_specs_2026_09_11_issue_22_show_existing_requests_at_the_bottom_of_stage_derivation, docs_superpowers_specs_2026_09_11_pipeline_control_room_design_pipeline_snapshot [INFERRED 0.85]

## Communities (25 total, 9 thin omitted)

### Community 0 - "Implement-Issue Skill Flow"
Cohesion: 0.07
Nodes (47): Round prompt template, auto-implement-issue skill, Codex as product owner's stand-in, Ready for staging ending, Unattended overrides, Spec review prompt template, arch-change ADR gate, The briefing (Step 2b) (+39 more)

### Community 1 - "PRD and Product Skills"
Cohesion: 0.07
Nodes (39): Part 1 playbook (second screen), Pipeline page as the facilitator control room, AI breakdown (proposal-only agent), Bug intake form and debugging route (R24), PRD Decision log (D1-D39), Blocking docs-drift Stop hook, In-app feature request interview (R23), implement-issue skill (+31 more)

### Community 2 - "Smoke Package Dependencies"
Cohesion: 0.07
Nodes (26): eslint, @eslint/js, @types/node, typescript, typescript-eslint, description, devDependencies, eslint (+18 more)

### Community 3 - "Ship Script Library"
Cohesion: 0.12
Nodes (8): comment(), dry(), fail(), merge_when_green(), pr_head_sha(), run(), lib.sh script, wait_for()

### Community 4 - "Triage and Readiness Rubric"
Cohesion: 0.14
Nodes (21): Architecture change test, Feature request issue form, Readiness rubric (clarity, complexity, risk), seed-requests skill, Triage board issue, triage-requests skill, Issue-body refinement section, Spec #19: accent color to oxblood (+13 more)

### Community 5 - "Interview Adapter and Pipeline Specs"
Cohesion: 0.11
Nodes (20): implement-issue skill, Skills never merge pull requests, Readiness formula clarity*2 + (6-complexity) + (6-risk), Anthropic interview adapter, Fake interview adapter, InterviewModel seam, report_turn tool-call state pattern, Vendored rubric copy in the interview prompt (+12 more)

### Community 6 - "Root Package Scripts"
Cohesion: 0.11
Nodes (16): devDependencies, prettier, yaml, engines, node, prettier, name, private (+8 more)

### Community 7 - "Pipeline Ship Design"
Cohesion: 0.14
Nodes (14): Kaizen Tasks Assembly Line Design Spec, Playwright smoke package, Agentic Feature Request Interview Design, FeatureRequestSummary contract, RequestsSoFar component, Redis action lock and concurrency group, Facilitator allowlist and deploy passphrase guard, POST /pipeline/issues/{n}/deploy-staging (+6 more)

### Community 8 - "CI/CD and Railway Plans"
Cohesion: 0.22
Nodes (11): CI/CD lane log, promote workflow and the staging SHA gate, Railway setup for Kaizen Tasks, Staging created by duplicating production, Railway wait-for-CI, Ship sequence: staging read-back, release cut, promotion, close as shipped, Pinned Triage board issue and idempotent label writes, Kaizen Tasks CI/CD and Railway Implementation Plan (+3 more)

### Community 9 - "TypeScript Config"
Cohesion: 0.18
Nodes (10): compilerOptions, forceConsistentCasingInFileNames, module, moduleResolution, noEmit, skipLibCheck, strict, target (+2 more)

### Community 10 - "Playwright Smoke Tests"
Cohesion: 0.25
Nodes (6): @playwright/test, aiTimeoutMs, AI_TIMEOUT_MS, AiState, CHIP, oneLine()

### Community 11 - "Interview SSE Streaming"
Cohesion: 0.40
Nodes (5): Caddy flush_interval -1 must not be set, readConversationStream web SSE parser, feature_request_conversations table, SSE stream protocol (delta/state/error/done), Finish with what we have

### Community 12 - "Prettier Config"
Cohesion: 0.40
Nodes (4): printWidth, proseWrap, singleQuote, trailingComma

### Community 13 - "Workspace Setup Script"
Cohesion: 0.60
Nodes (4): NVM_DIR, problem(), run(), setup-workspace.sh script

### Community 14 - "Accent Color and Theme Toggle"
Cohesion: 0.50
Nodes (4): accent-tokens.test.ts source-text assertions, --brand single accent variable, CSS relative color syntax derivation, Cycling ThemeToggle (light -> dark -> system)

### Community 15 - "Label Setup Script"
Cohesion: 0.83
Nodes (3): label(), run(), setup-labels.sh script

## Knowledge Gaps
- **84 isolated node(s):** `printWidth`, `proseWrap`, `singleQuote`, `trailingComma`, `name` (+79 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 116 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **9 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Readiness rubric (clarity, complexity, risk)` connect `Triage and Readiness Rubric` to `Interview Adapter and Pipeline Specs`, `Pipeline Ship Design`?**
  _High betweenness centrality (0.024) - this node is a cross-community bridge._
- **Why does `Kaizen Tasks Assembly Line Implementation Plan` connect `PRD and Product Skills` to `CI/CD and Railway Plans`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **What connects `printWidth`, `proseWrap`, `singleQuote` to the rest of the system?**
  _84 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Implement-Issue Skill Flow` be split into smaller, more focused modules?**
  _Cohesion score 0.07030527289546716 - nodes in this community are weakly interconnected._
- **Should `PRD and Product Skills` be split into smaller, more focused modules?**
  _Cohesion score 0.07152496626180836 - nodes in this community are weakly interconnected._
- **Should `Smoke Package Dependencies` be split into smaller, more focused modules?**
  _Cohesion score 0.07407407407407407 - nodes in this community are weakly interconnected._
- **Should `Ship Script Library` be split into smaller, more focused modules?**
  _Cohesion score 0.11688311688311688 - nodes in this community are weakly interconnected._