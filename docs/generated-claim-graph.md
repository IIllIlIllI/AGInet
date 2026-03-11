# Generated Claim Graph

- **source**: latest_report
- **run_id**: run-20260311-195453
- **timestamp_utc**: 20260311-195453
- **graph_variant**: baseline

```mermaid
flowchart TD
    c_dataset_verified["c_dataset_verified\nA dataset-backed signal supports the verified interpretation.\n[h_verified]"]
    c_forum_burst["c_forum_burst\nA forum burst suggests coordinated or brigaded amplification.\n[h_brigaded]"]
    c_blog_analysis["c_blog_analysis\nA derivative analysis blog offers mixed support and interpretation.\n[h_uncertain]"]
    c_verified_vs_brigaded["c_verified_vs_brigaded\nVerified and brigaded interpretations are in tension."]
    c_dataset_verified -->|"supports (0.9)"| c_verified_vs_brigaded
    c_forum_burst -->|"supports (0.8)"| c_verified_vs_brigaded
    c_dataset_verified -.->|"contradicts (0.7)"| c_forum_burst
    c_blog_analysis -->|"elaborates (0.4)"| c_dataset_verified
    c_blog_analysis -.->|"speculative (0.3)"| c_forum_burst
```

## Summary

- **claim_count**: 4
- **edge_count**: 5
- **relation_counts**: {'supports': 2, 'contradicts': 1, 'elaborates': 1, 'speculative': 1}
- **contradiction_density**: 0.2

## Support by Hypothesis

- **h_brigaded**: -0.7000
- **h_uncertain**: 0.0000
- **h_verified**: 0.0000
