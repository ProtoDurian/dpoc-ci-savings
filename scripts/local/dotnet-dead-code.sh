#!/usr/bin/env bash
set -euo pipefail

mode="${1:---llm}"
strict_filter="${DEAD_CODE_RULE_FILTER:-Unused|NeverInstantiated|NeverUsed|NotAccessed|NeverSubscribed|UnassignedField}"
llm_filter="${DEAD_CODE_LLM_RULE_FILTER:-.*}"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
solution="$(find "${root}" -maxdepth 1 -name '*.slnx' 2>/dev/null | head -n 1)"

[ "${mode}" != "--strict" ] && [ "${mode}" != "--strict-all" ] && [ "${mode}" != "--strict-production" ] && [ "${mode}" != "--llm" ] && echo "❌ mode must be --strict, --strict-all, --strict-production, or --llm" >&2 && exit 1
[ -z "${solution}" ] && echo "❌ No .slnx solution found in ${root}" >&2 && exit 1

echo "🔧 Restoring repo-local .NET tools..."
dotnet tool restore >/dev/null

shopt -s nullglob
production_projects=("${root}"/App*/*.csproj "${root}"/Lib*/*.csproj)
[ "${#production_projects[@]}" -eq 0 ] && echo "❌ No App*/Lib* production projects found" >&2 && exit 1

# Build once (inspectcode analyses the Debug configuration); both inspections then skip their own build.
echo "🔨 Building the solution once for both inspections..."
dotnet build "${solution}" -c Debug -nologo -v q

failed=0

# --strict: run both inspections at the same time (they share the one build above), then print each log in order.
if [ "${mode}" = "--strict" ]; then
  logs="$(mktemp -d)"
  echo "🔍 Strict dead-code inspection: all projects + production projects (parallel)"
  dn-inspect "${solution}" --no-build --filter "${strict_filter}" >"${logs}/all.log" 2>&1 &
  all_pid=$!
  dn-inspect --projects "${production_projects[@]}" --no-build --filter "${strict_filter}" >"${logs}/prod.log" 2>&1 &
  prod_pid=$!
  wait "${all_pid}" && all_rc=0 || all_rc=$?
  wait "${prod_pid}" && prod_rc=0 || prod_rc=$?
  echo "🔍 Strict dead-code inspection: all projects"
  cat "${logs}/all.log"
  if [ "${all_rc}" -eq 0 ]; then echo "✅ all projects: no issues found"; else failed=1 && echo "❌ all projects: issues found"; fi
  echo "🔍 Strict dead-code inspection: production projects"
  cat "${logs}/prod.log"
  if [ "${prod_rc}" -eq 0 ]; then echo "✅ production projects: no issues found"; else failed=1 && echo "❌ production projects: issues found"; fi
  rm -rf "${logs}"
fi

if [ "${mode}" = "--strict-all" ]; then
  echo "🔍 Strict dead-code inspection: all projects"
  if dn-inspect "${solution}" --no-build --filter "${strict_filter}"; then
    echo "✅ all projects: no issues found"
  else
    failed=1
    echo "❌ all projects: issues found"
  fi
fi

if [ "${mode}" = "--strict-production" ]; then
  echo "🔍 Strict dead-code inspection: production projects"
  if dn-inspect --projects "${production_projects[@]}" --no-build --filter "${strict_filter}"; then
    echo "✅ production projects: no issues found"
  else
    failed=1
    echo "❌ production projects: issues found"
  fi
fi

if [ "${mode}" = "--llm" ]; then
  echo "📝 LLM dead-code review: all projects"
  dn-inspect "${solution}" --no-build --filter "${llm_filter}" || true

  echo "📝 LLM dead-code review: production projects"
  dn-inspect --projects "${production_projects[@]}" --no-build --filter "${llm_filter}" || true
fi

[ "${failed}" -ne 0 ] && exit 1

echo "✅ Dead-code inspection complete"
