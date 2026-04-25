package runtime

import (
	"fmt"
	"strings"

	"codexflow/internal/codex"
	"codexflow/internal/store"
)

func toSessionSummary(record store.SessionRecord, pendingApprovals int) SessionSummary {
	var lastTurnID string
	var lastTurnStatus string
	if len(record.Thread.Turns) > 0 {
		lastTurn := record.Thread.Turns[len(record.Thread.Turns)-1]
		lastTurnID = lastTurn.ID
		lastTurnStatus = lastTurn.Status
	}

	effectiveLoaded := record.Loaded && !record.Runtime.Ended

	return SessionSummary{
		ID:               record.Thread.ID,
		Name:             optionalString(record.Thread.Name),
		Preview:          record.Thread.Preview,
		CWD:              record.Thread.CWD,
		Source:           codex.SourceLabel(record.Thread.Source),
		Status:           record.Thread.Status.Type,
		ActiveFlags:      cloneStrings(record.Thread.Status.ActiveFlags),
		Loaded:           effectiveLoaded,
		UpdatedAt:        record.Thread.UpdatedAt,
		CreatedAt:        record.Thread.CreatedAt,
		ModelProvider:    record.Thread.ModelProvider,
		Branch:           codex.GitBranch(record.Thread.GitInfo),
		PendingApprovals: pendingApprovals,
		LastTurnID:       lastTurnID,
		LastTurnStatus:   lastTurnStatus,
		AgentNickname:    optionalString(record.Thread.AgentNickname),
		AgentRole:        optionalString(record.Thread.AgentRole),
		Ended:            record.Runtime.Ended,
	}
}

func toSessionDetail(record store.SessionRecord, pendingApprovals int) SessionDetail {
	turns := make([]TurnDetail, 0, len(record.Thread.Turns))
	for _, turn := range record.Thread.Turns {
		turns = append(turns, toTurnDetail(turn, record.Runtime))
	}

	return SessionDetail{
		Summary: toSessionSummary(record, pendingApprovals),
		Turns:   turns,
	}
}

func toTurnDetail(turn codex.Turn, runtimeState store.SessionRuntime) TurnDetail {
	detail := TurnDetail{
		ID:          turn.ID,
		Status:      turn.Status,
		Diff:        runtimeState.LatestDiffByTurn[turn.ID],
		Plan:        make([]PlanStep, 0),
		Items:       make([]TurnItem, 0, len(turn.Items)),
		StartedAt:   derefInt64(turn.StartedAt),
		CompletedAt: derefInt64(turn.CompletedAt),
		DurationMs:  derefInt64(turn.DurationMs),
	}

	if turn.Error != nil {
		detail.Error = turn.Error.Message
	}

	if plan, ok := runtimeState.LatestPlanByTurn[turn.ID]; ok {
		detail.PlanExplanation = optionalString(plan.Explanation)
		detail.Plan = make([]PlanStep, 0, len(plan.Plan))
		for _, step := range plan.Plan {
			detail.Plan = append(detail.Plan, PlanStep{Step: step.Step, Status: step.Status})
		}
	}

	for _, item := range turn.Items {
		detail.Items = append(detail.Items, normalizeItem(item))
	}

	return detail
}

func normalizeItem(item map[string]any) TurnItem {
	itemType, _ := item["type"].(string)
	id, _ := item["id"].(string)

	result := TurnItem{
		ID:       id,
		Type:     itemType,
		Metadata: map[string]string{},
	}

	switch itemType {
	case "userMessage":
		result.Title = "User Prompt"
		result.Body = codex.FirstUserText([]map[string]any{item})
	case "agentMessage":
		result.Title = "Agent"
		result.Body, _ = item["text"].(string)
	case "plan":
		result.Title = "Plan"
		result.Body, _ = item["text"].(string)
	case "reasoning":
		result.Title = "Reasoning"
		if summary, ok := item["summary"].([]any); ok {
			result.Body = joinAny(summary, "\n")
		}
	case "commandExecution":
		result.Title = "Command"
		result.Body, _ = item["command"].(string)
		result.Status, _ = item["status"].(string)
		if output, ok := item["aggregatedOutput"].(string); ok {
			result.Auxiliary = output
		}
		if cwd, ok := item["cwd"].(string); ok {
			result.Metadata["cwd"] = cwd
		}
	case "fileChange":
		result.Title = "File Change"
		result.Status, _ = item["status"].(string)
		if changes, ok := item["changes"].([]any); ok {
			files := summarizeFileChanges(changes)
			if len(files) > 0 {
				result.Body = strings.Join(files, "\n")
				result.Metadata["changeCount"] = fmt.Sprintf("%d", len(files))
			} else {
				result.Body = fmt.Sprintf("%d file changes", len(changes))
				result.Metadata["changeCount"] = fmt.Sprintf("%d", len(changes))
			}
		}
	case "mcpToolCall":
		result.Title = "MCP Tool"
		result.Body = fmt.Sprintf("%v/%v", item["server"], item["tool"])
	case "dynamicToolCall":
		result.Title = "Tool Call"
		result.Body = fmt.Sprintf("%v:%v", item["namespace"], item["tool"])
	case "collabAgentToolCall":
		result.Title = "Delegation"
		result.Body, _ = item["prompt"].(string)
		result.Status, _ = item["status"].(string)
	default:
		result.Title = strings.Title(itemType)
	}

	if result.Body == "" {
		result.Body = summarizeUnknown(item)
	}
	return result
}

func summarizeUnknown(item map[string]any) string {
	parts := make([]string, 0, 4)
	for _, key := range []string{"status", "review", "result"} {
		if text, ok := item[key].(string); ok && text != "" {
			parts = append(parts, text)
		}
	}
	return strings.Join(parts, " · ")
}

func joinAny(values []any, sep string) string {
	parts := make([]string, 0, len(values))
	for _, value := range values {
		if text, ok := value.(string); ok && text != "" {
			parts = append(parts, text)
		}
	}
	return strings.Join(parts, sep)
}

func optionalString(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func derefInt64(value *int64) int64 {
	if value == nil {
		return 0
	}
	return *value
}

func cloneStrings(values []string) []string {
	if len(values) == 0 {
		return []string{}
	}
	return append([]string{}, values...)
}

func summarizeFileChanges(changes []any) []string {
	files := make([]string, 0, len(changes))
	seen := make(map[string]struct{}, len(changes))

	for _, change := range changes {
		changeMap, ok := change.(map[string]any)
		if !ok {
			continue
		}

		oldPath := stringFieldAny(changeMap, "oldPath")
		newPath := stringFieldAny(changeMap, "newPath")
		if oldPath != "" && newPath != "" && oldPath != newPath {
			addUniqueFile(&files, seen, fmt.Sprintf("%s -> %s", oldPath, newPath))
			continue
		}

		for _, key := range []string{"path", "filePath", "relativePath", "newPath", "oldPath"} {
			if value := stringFieldAny(changeMap, key); value != "" {
				addUniqueFile(&files, seen, value)
				break
			}
		}
	}

	return files
}

func stringFieldAny(values map[string]any, key string) string {
	if value, ok := values[key].(string); ok {
		return strings.TrimSpace(value)
	}
	return ""
}

func addUniqueFile(files *[]string, seen map[string]struct{}, value string) {
	if value == "" {
		return
	}
	if _, ok := seen[value]; ok {
		return
	}
	seen[value] = struct{}{}
	*files = append(*files, value)
}

func requestKind(method string) string {
	switch method {
	case "item/commandExecution/requestApproval":
		return "command"
	case "item/fileChange/requestApproval":
		return "fileChange"
	case "item/permissions/requestApproval":
		return "permissions"
	case "item/tool/requestUserInput":
		return "userInput"
	default:
		return "generic"
	}
}
