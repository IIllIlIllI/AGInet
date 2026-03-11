# AGInet System Map

## High-Level Architecture

```mermaid
flowchart TD
    A[Input Layer<br/>queries, documents, media, claims] --> B[Structural Epistemic Layer<br/>claim graph, provenance, independence, contradiction]
    B --> C[Cultural Intelligence Layer<br/>memes, slang, propaganda, coded language, belief systems]
    C --> D[Agent Council<br/>Batman, Harley, Socrates, Athena, Rorschach, Crab]
    D --> E[Governance Layer<br/>ranking, promotion, escalation, uncertainty handling]
    E --> F[Output Layer<br/>answers, explanations, teaching paths, warnings]

    E --> G[Observability Layer<br/>drift, graph observatory, poisoning detection]
    E --> H[Memory Layer<br/>council archive, immune memory, run history]
    E --> I[Curiosity Engine<br/>counterfactuals, cross-domain analogy, scenario exploration]
    G --> J[Long-Horizon Foresight<br/>weather map, distortion monitor, evolution engine, great filter]
    H --> J
    I --> J
    J --> D


flowchart TB
    subgraph Input
        A1[Queries]
        A2[Documents]
        A3[Social Posts]
        A4[Music / Memes]
    end

    subgraph Structural_Epistemics
        B1[Claim Extraction]
        B2[Claim Graph]
        B3[Provenance Tracking]
        B4[Independence & Diversity]
        B5[Contradiction Analysis]
        B6[Semantic Drift]
    end

    subgraph Cultural_Intelligence
        C1[Narrative / Memetic]
        C2[Linguistic / Semantic]
        C3[Influence / Control]
        C4[Incentive / Power]
        C5[Belief / Identity]
    end

    subgraph Council
        D1[Batman<br/>structural investigator]
        D2[Harley<br/>fringe / psyche]
        D3[Socrates<br/>logical interrogation]
        D4[Athena<br/>synthesis]
        D5[Rorschach<br/>bias audit]
        D6[Crab<br/>singularity dampener]
    end

    subgraph Governance
        E1[Promotion Governor]
        E2[Trust Bands]
        E3[Escalation Rules]
        E4[Human-in-the-Loop]
    end

    subgraph Observability
        F1[Run Drift Observatory]
        F2[Claim Graph Observatory]
        F3[Poisoning Detector]
        F4[Mode Comparison]
        F5[Artifact Doctor]
    end

    subgraph Memory
        G1[Council Memory Archive]
        G2[Cultural Immune Memory]
        G3[Resolution Logs]
        G4[History / Graph History]
    end

    subgraph Exploration
        H1[Curiosity Engine]
        H2[Counterfactual Generator]
        H3[Fiction Scenario Mining]
    end

    subgraph Foresight
        I1[Reality Distortion Monitor]
        I2[Memetic Weather Map]
        I3[Memetic Immune System]
        I4[Cultural Evolution Engine]
        I5[Great Filter Analysis]
    end

    subgraph Output
        J1[Answers]
        J2[Warnings]
        J3[Teaching Paths]
        J4[Intervention Ideas]
    end

    A1 --> B1
    A2 --> B1
    A3 --> B1
    A4 --> B1

    B1 --> B2
    B2 --> B3
    B2 --> B4
    B2 --> B5
    B5 --> B6

    B6 --> C1
    B6 --> C2
    B6 --> C3
    B6 --> C4
    B6 --> C5

    C1 --> D1
    C2 --> D2
    C3 --> D3
    C4 --> D4
    C5 --> D5
    B2 --> D1
    B3 --> D1
    B5 --> D3
    B6 --> D5
    I5 --> D6

    D1 --> E1
    D2 --> E1
    D3 --> E3
    D4 --> E2
    D5 --> E3
    D6 --> E4

    E1 --> J1
    E2 --> J1
    E3 --> J2
    E4 --> J4

    E1 --> F1
    E1 --> F2
    E1 --> F3
    E1 --> F4
    E1 --> F5

    F1 --> G4
    F2 --> G4
    F3 --> G2
    F4 --> G3
    F5 --> G3

    G1 --> D4
    G2 --> I3
    G3 --> D5
    G4 --> I4

    H1 --> D2
    H2 --> D3
    H3 --> D6

    I1 --> D2
    I2 --> D4
    I3 --> E3
    I4 --> D4
    I5 --> D6

    D4 --> J3
