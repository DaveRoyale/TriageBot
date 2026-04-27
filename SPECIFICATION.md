# Compliance Incident Triage Bot — Proof of Concept Specification

**Version:** 0.1 (draft)
**Date:** 2026-04-26
**Status:** PoC scope

---

## 1. Purpose

A web-based chat bot that guides general bank staff (non-compliance specialists) through documenting a compliance incident early in its lifecycle. The bot asks probing questions to surface what is known, identifies likely incident types from the conversation, and produces a structured report as email text for the compliance team and senior management.

The goal is to automate the early documentation process and give compliance professionals a consistent, well-structured picture of an incident before they engage directly with the reporter.

---

## 2. Goals and Non-Goals

### In scope (PoC)
- Guided, open-ended conversation that discovers incident type from staff responses
- Support for **privacy breaches** and **Banking Code of Practice breaches** as the initial incident types
- Dynamic report structure: core sections present in all reports, type-specific sections added based on incident types identified
- Compliance flag generation (e.g. possible regulatory notification obligations) included in the report for the compliance team's assessment
- Periodic conversation summary displayed to the user during the chat
- Report output as formatted email text, with suggested recipient groups, ready for the user to copy and send
- Single EC2 instance deployment suitable for a bank's private cloud

### Out of scope (PoC)
- User authentication and access control
- Session persistence (each conversation is fresh)
- Direct email sending
- Integration with GRC platforms, ticketing systems, or case management tools
- Attachment or document handling
- Meeting specific regulatory reporting obligations (the bot flags possibilities; it does not produce regulatory submissions)
- Incident types beyond privacy breaches and Banking Code of Practice breaches

---

## 3. Users

**Primary user:** General bank staff with no compliance expertise. They may be stressed or uncertain when reporting an incident. The bot's tone is professional and neutral — its purpose is to document, not to reassure or advise.

**Report consumers:** Compliance team and senior management. They receive the email text and use it to understand the incident, assess compliance implications, and determine next steps.

---

## 4. System Architecture

### 4.1 Production deployment

All components run on a single EC2 instance within the bank's private cloud network.

```
Browser (staff member)
        │  HTTP
        ▼
┌─────────────────────────────────────┐
│  EC2 Instance (Ubuntu 22.04 LTS)    │
│                                     │
│  FastAPI application                │
│  ├── Serves static frontend files  │
│  ├── /api/chat endpoint             │
│  └── /api/report endpoint           │
│                                     │
│  Ollama (LLM serving)               │
│  └── Model: configurable            │
└─────────────────────────────────────┘
```

| Component | Choice | Notes |
|-----------|--------|-------|
| OS | Ubuntu 22.04 LTS | Clean, well-documented, strong Ollama support |
| Backend | Python 3.11 + FastAPI | Serves API and frontend static files from same process |
| Frontend | Plain HTML + vanilla JS | No build pipeline; message thread, input box, report panel |
| LLM serving | Ollama | Single-binary install, trivial model switching |
| Default model | Phi-3 Mini (3.8B) | Runs on CPU within instance RAM budget |

### Infrastructure

| Parameter | Value |
|-----------|-------|
| Instance type | `t3.large` (2 vCPU, 8GB RAM) for 3B model; `t3.xlarge` for 7B model |
| Storage | 30GB EBS gp3 (OS + Ollama + quantized model weights) |
| OS | Ubuntu 22.04 LTS |
| Network | Private subnet only; no public IP required |
| Ports exposed | Application port (8000) within private network only |
| Authentication | None (PoC; network boundary is the access control) |

### 4.2 Local development environment

During development the application runs on a local Mac. The Ollama + local model stack is replaced by the Anthropic API (Claude Haiku), which requires no local model weights and provides significantly faster iteration. The FastAPI backend and HTML/JS frontend are identical in both environments.

```
Browser (developer)
        │  HTTP (localhost)
        ▼
┌─────────────────────────────────────┐
│  Local Mac                          │
│                                     │
│  FastAPI application                │
│  ├── Serves static frontend files  │
│  ├── /api/chat endpoint             │
│  └── /api/report endpoint           │
└─────────────────────────────────────┘
        │  HTTPS
        ▼
  Anthropic API (Claude Haiku)
```

**Data handling note:** The Anthropic API is used with synthetic or fictional test incidents only during development. Real incident data must not leave the bank's private network.

### 4.3 LLM provider abstraction

The application routes all LLM calls through a single provider interface. The active provider is set by a config value:

- `anthropic` — uses the Anthropic SDK, model configurable (default: `claude-haiku-4-5`)
- `ollama` — uses the Ollama HTTP API, model configurable (default: `phi3`)

Switching providers or models requires only a config change. No application logic changes.

---

## 5. Conversation Design

### 5.1 Opening

The bot opens with a brief statement of its purpose and asks the staff member to describe the incident in their own words. It does not present a list of incident types or categories to choose from.

### 5.2 Discovery phase

The bot asks follow-up questions freely to explore the incident. Questions are driven by the LLM using the system prompt (see Section 6). The bot aims to establish:

- What happened
- When it occurred and when it was discovered
- Whether the incident is still occurring or has ceased
- What systems, data, or processes are involved
- Which customers or staff are affected, and approximately how many
- What actions have already been taken or are planned,
        - To understand what happened and why (cause(s) of the incident)
        - To understand who was affected
        - To mitigate impacts on customers or staff

As answers accumulate, the bot builds an internal picture of which incident type(s) may apply. The bot does not announce an incident type classification mid-conversation unless it is helpful to do so.

### 5.3 Handling unknowns

If a staff member does not know the answer to a question, the bot accepts this and records it as an unknown in the report. The bot may ask for a best estimate where appropriate, but does not press repeatedly. Specific guidance on handling unknowns for each incident type will be defined in the subsequent incident type design step.

### 5.4 Periodic summary

At natural breakpoints in the conversation (approximately every three to six exchanges, not after every question), the bot displays a brief summary of what it has captured so far. The summary includes:

- Incident type(s) identified or suspected
- Key facts recorded
- Key gaps or unknowns

This gives the user the opportunity to correct errors or volunteer additional information before the report is generated.

### 5.5 Report generation trigger

Report generation can be triggered two ways:

1. **User-initiated:** The user presses a "Generate Report" button at any point.
2. **Bot-initiated:** When the bot judges it has sufficient information for a useful initial report, it suggests to the user that enough has been captured and offers to generate the report.

After generation, the report is displayed in the UI alongside the conversation. The user can request the bot ask further questions and regenerate if needed.

### 5.6 Conversation length

The bot is guided to gather enough information for a report of approximately two pages. It should not allow the conversation to run on past the point where sufficient detail for an initial report has been gathered.

---

## 6. LLM Configuration

### 6.1 System prompt responsibilities

The base system prompt defines the bot's:

- Identity and purpose (compliance incident documentation assistant for an Australian bank)
- Tone (professional, neutral, documentation-focused)
- High-level awareness of supported incident types
- Questioning strategy (open-ended discovery, follow-up probing)
- Rules for handling unknowns
- Criteria for judging when sufficient information has been gathered
- Summary generation cadence
- Core report format (sections present in every report)
- Instruction to emit a structured JSON sidecar on every response (see 6.4)

Type-specific questioning guidance, report section formats, and regulatory flag logic are held in separate guidance files (see 6.4) and are not embedded in the base system prompt.

### 6.2 Conversation history

The full conversation history is passed to the LLM with each API call. The assembled system prompt (base + any injected guidance) and conversation history together constitute the LLM context on every turn.

### 6.4 Incident type guidance and dynamic context injection

Detailed guidance for each incident type is stored in standalone markdown files under `guidance/`. Each file contains:

- Key questions to establish for that incident type
- The type-specific report section format
- Regulatory flag conditions and flag wording

The LLM appends a structured JSON sidecar to every response:

```json
{"incident_types": ["privacy_breach"], "ready_for_report": false}
```

The backend strips this sidecar before displaying the response, accumulates the detected incident types across the conversation, and injects the corresponding guidance files into the system prompt on every subsequent turn. This means the LLM receives progressively more specific guidance as the incident type becomes clearer.

**Supported incident types and guidance files:**

| Incident type | Guidance file | Status |
|---------------|---------------|--------|
| Privacy breach | `guidance/privacy_breach.md` | Initial version complete |
| Banking Code of Practice breach | `guidance/banking_code.md` | Initial version complete |

**Adding a new incident type** requires only:
1. Creating a new guidance file in `guidance/`
2. Adding one entry to the `KNOWN_TYPES` dict in `app/context.py`
3. Adding the type name to the incident types list in the base system prompt

No other code changes are required. This mechanism works identically across all LLM providers (Gemini, Anthropic, Ollama).

### 6.3 Models

| Environment | Provider | Default model | Notes |
|-------------|----------|---------------|-------|
| Local development | Anthropic API | `claude-haiku-4-5` | Fast, capable, no local weights needed |
| EC2 deployment | Ollama | `phi3` (Phi-3 Mini 3.8B) | CPU inference, fits within t3.large RAM |

If local model quality is insufficient on EC2, upgrade to `llama3.1:8b` or `mistral:7b` by changing the model config value and pulling the new model via Ollama.

---

## 7. Report Design

### 7.1 Principles

- Maximum approximately two pages of text
- Written for a compliance professional and senior management reader, not the original reporter
- Factual and neutral in tone — records what is known, what is suspected, and what is unknown
- Does not contain legal conclusions; compliance flags are framed as matters for the compliance team to assess
- Further requirements to be added at a subsequent stage

### 7.2 Core sections (present in every report)

These sections appear regardless of incident type.

| Section | Content |
|---------|---------|
| **Incident Summary** | Narrative description of what happened, when it occurred, and when it was discovered |
| **Scope** | Systems, processes, data, or products involved; number of customers or staff affected (or best estimate / unknown) |
| **Actions Already Taken** | Steps taken by the reporting area since the incident was identified |
| **Compliance Implications** | Incident type(s) that may apply; regulatory notification obligations that may be triggered — flagged for compliance team assessment, not as conclusions |
| **Material Unknowns** | Significant gaps in current understanding that the compliance team should be aware of |
| **Suggested Recipients** | Recommended recipient groups for this email (e.g. Group Compliance, Privacy Officer, relevant business line risk team) |

### 7.3 Type-specific sections

Type-specific sections are defined in guidance files (see Section 6.4) and injected into the LLM context when the relevant incident type is detected. If both types are identified, both section sets are included.

**Privacy breach** (`guidance/privacy_breach.md`):

| Section | Content |
|---------|---------|
| **Personal Information Involved** | Categories and type of personal information affected; approximate number of individuals; whether customers, staff, or both |
| **Nature of the Breach** | How the breach occurred; whether contained; actions to address causes; any ongoing investigation |
| **Exposure** | Whether unauthorised access has taken place and by whom; whether information has left the bank's control; risk of harm to individuals; any steps to delete or retrieve disclosed information |
| **Individual Notification** | Whether affected individuals have been notified; whether notification is planned and timing |

Regulatory flags: NDB scheme assessment (Privacy Act 1988); Privacy Officer notification.

**Banking Code of Practice** (`guidance/banking_code.md`):

| Section | Content |
|---------|---------|
| **Customers and Products Affected** | Which customers; approximate number; products or services involved; whether any affected customers are in hardship or vulnerable circumstances |
| **Nature of the Potential Breach** | What obligation may have been failed; whether a single incident or ongoing issue |
| **Customer Impact** | Direct financial impact; other impacts (e.g. inability to access services, lack of financial understanding) |
| **Remediation** | Steps taken or planned to remediate customer impact and correct underlying process |

Regulatory flags: AFCA notification; ASIC/APRA notification; internal escalation to CRO/Board Risk Committee.

### 7.4 Extensibility

New incident types are added by:
1. Creating a guidance file in `guidance/` with key questions, report section format, and regulatory flag conditions
2. Adding one entry to `KNOWN_TYPES` in `app/context.py`
3. Adding the type name to the base system prompt's incident types list

No other code changes are required.

### 7.5 Output format

The report is rendered as formatted email text within the UI. The user copies it manually and sends it via their normal email client. The bot does not send email directly.

---

## 8. Subsequent Design Steps

| # | Item | Status |
|---|------|--------|
| 1 | Privacy breach — type-specific report sections, key questions, NDB flag conditions | Initial version complete in `guidance/privacy_breach.md` — to be refined through testing |
| 2 | Banking Code of Practice — type-specific report sections, Code obligations to probe, AFCA/ASIC/APRA flag conditions | Initial version complete in `guidance/banking_code.md` — to be refined through testing |
| 3 | Handling unknowns by incident type — specific bot behaviour for material unknowns within each type | To be addressed through iterative testing of example conversations |
| 4 | System prompt refinement — base system prompt and guidance file content tuned against real example scenarios | Ongoing; initial versions in place |
| 5 | Additional incident types (AML/CTF, operational risk, market conduct) | Deferred post-PoC |

---

## 9. Future Considerations (post-PoC)

The following are out of scope for the PoC but should inform design decisions to avoid painting into a corner:

- **Authentication:** SSO integration for staff identity; report should capture reporter name and team
- **Session persistence:** Allow a conversation to be resumed if interrupted
- **GRC / ticketing integration:** Push the completed report directly into a case management or GRC system
- **Audit logging:** Retain conversation logs for compliance purposes
- **Additional incident types:** AML/CTF, operational risk events, market conduct, etc.
- **Upgraded LLM:** Move to a larger model (13B+) on a GPU-enabled instance if PoC quality is insufficient
