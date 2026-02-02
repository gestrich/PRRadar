# Review Summary: ${TITLE}

## Overview
${OVERVIEW_DESCRIPTION}

**Files Changed:** ${FILE_COUNT}
**Total Segments:** ${SEGMENT_COUNT}
**Applicable Rules:** ${RULE_COUNT}

---

${FOR_EACH_FILE}
## File: `${FILE_PATH}`

${FOR_EACH_SEGMENT}
### Segment ${SEGMENT_NUMBER}: ${SEGMENT_NAME} (${CHANGE_STATUS})

```${LANGUAGE}
${SEGMENT_DIFF}
```

#### Rule Reviews
${FOR_EACH_RULE}
- [ ] **${RULE_NAME}** | Score: ? | Details: ?
${END_FOR_EACH_RULE}

---
${END_FOR_EACH_SEGMENT}
${END_FOR_EACH_FILE}

## Summary

### Violations by Rule

| Rule | Violations | Documentation |
|------|------------|---------------|
${FOR_EACH_VIOLATED_RULE}
| ${RULE_NAME} | ${VIOLATION_COUNT} | [${RULE_DOC_TITLE}](${RULE_DOC_URL}) |
${END_FOR_EACH_VIOLATED_RULE}

### Results by File

| File | Segments | Highest Score | Primary Concern |
|------|----------|---------------|-----------------|
${FOR_EACH_FILE}
| ${FILE_NAME} | ${SEGMENT_COUNT} | ${HIGHEST_SCORE} | ${PRIMARY_CONCERN} |
${END_FOR_EACH_FILE}

### Violation Details

${FOR_EACH_VIOLATED_RULE}
#### ${RULE_NAME} (${VIOLATION_COUNT} segment(s)) — [Documentation](${RULE_DOC_URL})

${FOR_EACH_VIOLATION}
**${FILE_NAME} → ${SEGMENT_NAME}** (Score: ${SCORE}, Line: ${LINE_NUMBER})
${VIOLATION_DETAILS}
```${LANGUAGE}
${VIOLATION_CODE_SNIPPET}
```
${END_FOR_EACH_VIOLATION}
${END_FOR_EACH_VIOLATED_RULE}

### Recommended Actions

${FOR_EACH_RECOMMENDATION}
${RECOMMENDATION_NUMBER}. ${RECOMMENDATION_TEXT}
${END_FOR_EACH_RECOMMENDATION}
