#!/bin/bash

# Sync Personality from SKILL.md & roles/*/SOUL.md to agents.json (v2.0)
# Source of Truth: SKILL.md (trait/summary/keywords) + roles/*/SOUL.md (soul)
#
# Usage: ./scripts/sync_personality.sh [--dry-run]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SKILLS_DIR="$REPO_DIR/skills"
ROLES_DIR="$REPO_DIR/roles"
AGENTS_JSON="$REPO_DIR/agents.json"
DRY_RUN=false

[ "$1" = "--dry-run" ] && DRY_RUN=true

echo "🔄 Personality Sync v2.0: SKILL.md + roles/SOUL.md → agents.json"
echo "================================================================"
echo "Repo: $REPO_DIR"
echo ""

# Check jq is available
if ! command -v jq &> /dev/null; then
    echo "❌ Error: jq is required but not installed."
    exit 1
fi

# Backup original
if [ "$DRY_RUN" = false ]; then
    cp "$AGENTS_JSON" "${AGENTS_JSON}.bak.$(date +%Y%m%d%H%M%S)"
fi

# Extract all personalities into a temp JSON array
PERSONALITIES=$(python3 - "$SKILLS_DIR" "$ROLES_DIR" << 'PYTHON_SCRIPT'
import sys
import re
import json
import os

skills_dir = sys.argv[1]
roles_dir = sys.argv[2]
results = []

# Role map: skill slug -> role name
role_map = {
    "task-hub-executor": "executor",
    "task-hub-collector": "collector",
    "task-hub-creator": "commander"
}

# Slug to agent name map (for matching roles/)
slug_to_name = {
    "taizi": "taizi",
    "answer": "answer",
    "xiaoxi": "xiaoxi"
}

# Role to agent dir map
role_to_agent = {
    "executor": "taizi",
    "collector": "answer",
    "commander": "xiaoxi"
}

# 1. Extract from SKILL.md files (trait, summary, keywords)
for skill_name in os.listdir(skills_dir):
    skill_path = os.path.join(skills_dir, skill_name, "SKILL.md")
    if not os.path.isfile(skill_path):
        continue

    with open(skill_path, 'r', encoding='utf-8') as f:
        content = f.read()

    trait_match = re.search(r'\*\*Trait\*\*:\s*(.+?)(?:\n|$)', content)
    summary_match = re.search(r'\*\*Summary\*\*:\s*(.+?)(?:\n|$)', content)
    keywords_match = re.search(r'\*\*Keywords\*\*:\s*(.+?)(?:\n|$)', content)

    if not trait_match:
        continue

    trait = trait_match.group(1).strip()
    summary = summary_match.group(1).strip() if summary_match else ""
    keywords_raw = keywords_match.group(1).strip() if keywords_match else ""

    if '、' in keywords_raw:
        keywords = [k.strip() for k in keywords_raw.split('、') if k.strip()]
    elif ',' in keywords_raw:
        keywords = [k.strip() for k in keywords_raw.split(',') if k.strip()]
    else:
        keywords = [keywords_raw] if keywords_raw else []

    role = role_map.get(skill_name, skill_name.replace("task-hub-", ""))

    results.append({
        "slug": skill_name,
        "role": role,
        "trait": trait,
        "summary": summary,
        "keywords": keywords,
        "soul": ""  # Will be filled from SOUL.md
    })

# 2. Extract soul from roles/*/SOUL.md
for agent_dir in os.listdir(roles_dir):
    soul_path = os.path.join(roles_dir, agent_dir, "SOUL.md")
    if not os.path.isfile(soul_path):
        continue

    with open(soul_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Extract soul content: title (H1) + ## 🎭 Persona section
    # Pattern: # Agent Name\n\n## 🎭 Persona\n- Role: ...
    lines = content.split('\n')
    soul_lines = []
    in_persona = False

    for line in lines:
        if line.startswith('# ') and not line.startswith('##'):
            # First line is the agent name/title
            soul_lines.append(line)
        elif '## 🎭' in line or '## 🧠' in line or '## Persona' in line:
            in_persona = True
            soul_lines.append(line)
        elif in_persona and line.startswith('## '):
            # Next section starts, stop
            break
        elif in_persona:
            soul_lines.append(line)

    soul = '\n'.join(soul_lines).strip()

    # Also get personality traits (**Trait**: or **Personality**:)
    trait_match = re.search(r'(?:^\*\*Trait\*\*|^\*\*Personality\*\*):\s*(.+?)(?:\n|$)', content, re.MULTILINE)
    soul_trait = trait_match.group(1).strip() if trait_match else ""

    # Map agent dir to slug
    agent_slug = slug_to_name.get(agent_dir, agent_dir)
    # Also find the role that maps to this agent
    mapped_role = None
    for role, ag in role_to_agent.items():
        if ag == agent_dir:
            mapped_role = role
            break

    for p in results:
        # Match by slug (task-hub-executor), by role (executor), or by role mapping
        if p['slug'] == f"task-hub-{agent_slug}" or p['role'] == agent_slug or p['role'] == mapped_role:
            if soul:
                p['soul'] = soul
            if soul_trait and not p['trait']:
                p['trait'] = soul_trait

print(json.dumps(results, ensure_ascii=False))
PYTHON_SCRIPT
)

if [ -z "$PERSONALITIES" ] || [ "$PERSONALITIES" = "[]" ]; then
    echo "❌ No personalities found in SKILL.md files"
    exit 1
fi

echo "📊 Found personalities for $(echo "$PERSONALITIES" | jq 'length') skills:"
echo "$PERSONALITIES" | jq -c '.[]' | while read -r p; do
    slug=$(echo "$p" | jq -r '.slug')
    trait=$(echo "$p" | jq -r '.trait')
    has_soul=$(echo "$p" | jq -r '.soul != ""')
    echo "  - $slug → trait: $trait | soul: $has_soul"
done

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "🟡 DRY RUN - Would update agents.json with:"
    echo "$PERSONALITIES" | jq '.'
    exit 0
fi

# Update agents.json
python3 - "$AGENTS_JSON" "$PERSONALITIES" << 'PYTHON_SCRIPT'
import sys
import json

agents_json_path = sys.argv[1]
personalities = json.loads(sys.argv[2])

with open(agents_json_path, 'r', encoding='utf-8') as f:
    agents = json.load(f)

personality_by_slug = {p['slug']: p for p in personalities}
personality_by_role = {p['role']: p for p in personalities}

# Role mapping from agents.json perspective (slug -> skill role)
agent_to_role = {
    "xiaoxi": "commander",
    "answer": "collector",
    "taizi": "executor"
}

updated_count = 0
for agent in agents['agents']:
    slug = agent.get('slug', '')
    role = agent.get('role', '')

    # Match by slug first (task-hub-executor), then by mapped role (commander/collector/executor)
    p = personality_by_slug.get(slug) or personality_by_role.get(agent_to_role.get(slug, ''))

    if p:
        agent['personality'] = {
            "trait": p['trait'],
            "summary": p['summary'],
            "keywords": p['keywords'],
            "soul": p.get('soul', '')
        }
        updated_count += 1
        soul_preview = p.get('soul', '')[:30] + '...' if p.get('soul', '') else 'N/A'
        print(f"  ✅ Updated {agent['name']} ({slug}) with trait: {p['trait']}")
        if p.get('soul'):
            print(f"     soul: {soul_preview}")
    else:
        print(f"  ⚠️  No personality found for {agent['name']} (slug={slug}, role={role})")

with open(agents_json_path, 'w', encoding='utf-8') as f:
    json.dump(agents, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f"\n✅ Synced {updated_count} agents")
PYTHON_SCRIPT

echo ""
echo "✅ Sync complete!"
