#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/richer-chatgpt-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
swiftc -module-cache-path "$test_dir/modules" \
  Richer/Core/Auth/ChatGPTIdentity.swift tools/tests/ChatGPTIdentityTests.swift \
  -o "$test_dir/identity-tests"
"$test_dir/identity-tests"
swiftc -module-cache-path "$test_dir/modules" \
  Richer/Core/LLM/LLMClient.swift Richer/Core/LLM/Providers/ChatGPTProvider.swift \
  tools/tests/ChatGPTProviderTests.swift -o "$test_dir/provider-tests"
"$test_dir/provider-tests"
