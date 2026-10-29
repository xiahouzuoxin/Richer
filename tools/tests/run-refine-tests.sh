#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/richer-refine-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
swiftc -parse-as-library -module-name RefineMigrationTests -module-cache-path "$test_dir/modules" \
  tools/tests/fixtures/LegacyRefineHistory.swift -o "$test_dir/seed-history"
"$test_dir/seed-history" "$test_dir/history.store"
swiftc -parse-as-library -module-name RefineMigrationTests -module-cache-path "$test_dir/modules" \
  Richer/Core/LLM/LLMClient.swift Richer/Core/Prompting/PromptTemplate.swift \
  Richer/Core/Prompting/DefaultPrompts.swift Richer/Features/Refine/RefineOptions.swift Richer/Features/Refine/RefinePromptStore.swift \
  Richer/Features/Cards/ActionCard.swift Richer/Features/History/HistoryEntry.swift \
  Richer/Features/History/HistoryStore.swift tools/tests/RefineTests.swift \
  -o "$test_dir/refine-tests"
"$test_dir/refine-tests" "$test_dir/history.store"
swiftc -parse-as-library -module-cache-path "$test_dir/modules" \
  Richer/Core/LLM/LLMClient.swift Richer/Features/Reply/ReplySettings.swift Richer/Features/Reply/ReplyService.swift \
  tools/tests/ReplyTests.swift -o "$test_dir/reply-tests"
"$test_dir/reply-tests"
