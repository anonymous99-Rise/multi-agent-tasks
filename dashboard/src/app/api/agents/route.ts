import { getServerSession } from "next-auth";
import { authOptions } from "@/lib/auth";
import { Octokit } from "octokit";
import { NextResponse } from "next/server";
import { getRepoInfo } from "@/lib/github";
import { encryptSecret } from "@/lib/crypto";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import path from "path";

// 心跳文件存储路径
const AGENTS_PATH = "agents.json";

// SOUL.md 和 IDENTITY.md 路径映射
// role → skill 目录映射（与 agents.json.role 字段对应）
const ROLE_SKILL_PATHS: Record<string, string> = {
  commander: "skills/task-hub-creator",   // 小溪 → task-hub-creator
  collector: "skills/task-hub-collector", // Answer → task-hub-collector
  executor:  "skills/task-hub-executor"    // 太子 → task-hub-executor
};

const getHeartbeatFile = () => {
  const dataDir = path.join(process.cwd(), "data");
  if (!existsSync(dataDir)) mkdirSync(dataDir, { recursive: true });
  return path.join(dataDir, "agent-heartbeats.json");
};

// 读取心跳
const readHeartbeats = (): Record<string, number> => {
  try {
    return JSON.parse(readFileSync(getHeartbeatFile(), "utf8"));
  } catch {
    return {};
  }
};

// 写入心跳
const writeHeartbeats = (heartbeats: Record<string, number>) => {
  writeFileSync(getHeartbeatFile(), JSON.stringify(heartbeats, null, 2));
};

// 读取 SOUL.md 和 IDENTITY.md
const loadSkillFiles = async (octokit: any, owner: string, repo: string, role: string) => {
  const skillPath = ROLE_SKILL_PATHS[role as keyof typeof ROLE_SKILL_PATHS];
  if (!skillPath) return { soul: null, identity: null };

  const result: { soul: string | null; identity: string | null } = { soul: null, identity: null };

  try {
    const { data: soulData }: any = await octokit.rest.repos.getContent({
      owner, repo, path: `${skillPath}/SOUL.md`
    });
    result.soul = Buffer.from(soulData.content, "base64").toString("utf-8");
  } catch {}

  try {
    const { data: identityData }: any = await octokit.rest.repos.getContent({
      owner, repo, path: `${skillPath}/IDENTITY.md`
    });
    result.identity = Buffer.from(identityData.content, "base64").toString("utf-8");
  } catch {}

  return result;
};

export async function GET() {
  const session: any = await getServerSession(authOptions);
  const token = session?.accessToken || process.env.GITHUB_TOKEN;
  if (!token) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const octokit = new Octokit({ auth: token });

  try {
    const { owner, repo } = await getRepoInfo(octokit);
    try {
      const { data }: any = await octokit.rest.repos.getContent({ owner, repo, path: AGENTS_PATH });
      const content = Buffer.from(data.content, "base64").toString("utf-8");
      const config = JSON.parse(content);

      const now = Date.now();
      const heartbeats = readHeartbeats();

      // 为每个 agent 加载 SOUL.md 和 IDENTITY.md
      const sanitizedAgents = await Promise.all(
        (config.agents || []).map(async (agent: any) => {
          const skillFiles = await loadSkillFiles(octokit, owner, repo, agent.role);
          return {
            ...agent,
            tgToken: agent.tgToken ? "********" : "",
            online: heartbeats[agent.name] && (now - heartbeats[agent.name] < 300000),
            soul: skillFiles.soul,
            identity: skillFiles.identity
          };
        })
      );

      return NextResponse.json({ agents: sanitizedAgents });
    } catch (e) {
      return NextResponse.json({ agents: [] });
    }
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function POST(req: Request) {
  const payload = await req.json();

  // 处理心跳上报 (不需要 Session 校验，通过 Token 校验或简单的 Agent 名称即可)
  if (payload.action === "heartbeat") {
    const heartbeats = readHeartbeats();
    heartbeats[payload.name] = Date.now();
    writeHeartbeats(heartbeats);
    return NextResponse.json({ success: true, timestamp: heartbeats[payload.name] });
  }

  // 处理 personality 从 SKILL.md 同步 (通过 GitHub API 读取，commit 更新 agents.json)
  if (payload.action === "sync_personality") {
    const session: any = await getServerSession(authOptions);
    const token = session?.accessToken || process.env.GITHUB_TOKEN;
    if (!token) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

    const octokit = new Octokit({ auth: token });
    const { owner, repo } = await getRepoInfo(octokit);

    // role → skill path 映射
    const roleSkillPaths: Record<string, string> = {
      commander: "skills/task-hub-creator/SKILL.md",
      collector: "skills/task-hub-collector/SKILL.md",
      executor:  "skills/task-hub-executor/SKILL.md"
    };

    // 读取 agents.json
    let agentsSha: string | undefined;
    let agentsContent: any;
    try {
      const { data }: any = await octokit.rest.repos.getContent({ owner, repo, path: AGENTS_PATH });
      agentsSha = data.sha;
      agentsContent = JSON.parse(Buffer.from(data.content, "base64").toString("utf-8"));
    } catch (e) {
      return NextResponse.json({ success: false, error: "Cannot read agents.json" });
    }

    // 从 SKILL.md 解析 personality 并更新对应 agent
    for (const agent of agentsContent.agents || []) {
      const skillPath = roleSkillPaths[agent.role];
      if (!skillPath) continue;

      try {
        const { data }: any = await octokit.rest.repos.getContent({ owner, repo, path: skillPath });
        const skillContent = Buffer.from(data.content, "base64").toString("utf-8");

        // 解析 personality 字段
        const traitMatch = skillContent.match(/\*\*Trait\*\*:\s*(.+?)(?:\n|$)/);
        const summaryMatch = skillContent.match(/\*\*Summary\*\*:\s*(.+?)(?:\n|$)/);
        const keywordsMatch = skillContent.match(/\*\*Keywords\*\*:\s*(.+?)(?:\n|$)/);
        const soulMatch = skillContent.match(/## 🎭 Persona\n([\s\S]+?)(?=\n##|\n---\n|$)/);

        agent.personality = {
          trait: traitMatch ? traitMatch[1].replace(/\(.+\)/, "").trim() : agent.personality?.trait || "",
          summary: summaryMatch ? summaryMatch[1].trim() : agent.personality?.summary || "",
          keywords: keywordsMatch
            ? keywordsMatch[1].split("、").map((k: string) => k.trim()).filter(Boolean)
            : agent.personality?.keywords || [],
          soul: soulMatch ? soulMatch[1].trim() : agent.personality?.soul || ""
        };
      } catch {
        // SKILL.md 不存在则跳过
      }
    }

    // 提交更新
    agentsContent.lastUpdated = new Date().toISOString();
    try {
      await octokit.rest.repos.createOrUpdateFileContents({
        owner, repo, path: AGENTS_PATH,
        message: "🔄 sync: Update personality from SKILL.md",
        content: Buffer.from(JSON.stringify(agentsContent, null, 2)).toString("base64"),
        sha: agentsSha,
      });
      return NextResponse.json({ success: true, message: "Personality synced from SKILL.md via GitHub API" });
    } catch (e: any) {
      return NextResponse.json({ success: false, error: e.message });
    }
  }

  const session: any = await getServerSession(authOptions);
  if (!session?.accessToken) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const octokit = new Octokit({ auth: session.accessToken });
  const { agents } = payload;


  try {
    const { owner, repo } = await getRepoInfo(octokit);

    // 1. 处理所有 Agent 的 Token 并存入 Secrets
    const { data: publicKey } = await octokit.rest.actions.getRepoPublicKey({ owner, repo });

    const agentsToSave = await Promise.all(agents.map(async (agent: any) => {
      if (agent.tgToken && agent.tgToken !== "********") {
        const encryptedValue = await encryptSecret(publicKey.key, agent.tgToken);
        // 增强命名规范：只允许大写字母、数字和下划线，非 ASCII 字符转换为拼音或 ID
        let safeName = agent.name.toUpperCase().replace(/[^A-Z0-9_]/g, '_');
        if (!safeName || safeName.startsWith('_')) {
          safeName = `ID_${agent.id}`;
        }
        const secretName = `AGENT_${safeName}_TOKEN`;

        await octokit.rest.actions.createOrUpdateRepoSecret({
          owner,
          repo,
          secret_name: secretName,
          encrypted_value: encryptedValue,
          key_id: publicKey.key_id,
        });

        return { ...agent, tgToken: `SECRET:${secretName}` };
      }
      return agent;
    }));

    // 2. 保存非敏感名册
    let sha: string | undefined = undefined;
    try {
      const { data }: any = await octokit.rest.repos.getContent({ owner, repo, path: AGENTS_PATH });
      sha = data.sha;
    } catch (e) {}

    await octokit.rest.repos.createOrUpdateFileContents({
      owner,
      repo,
      path: AGENTS_PATH,
      message: "🔐 Secure Update: Agent registry (tokens moved to Secrets)",
      content: Buffer.from(JSON.stringify({ agents: agentsToSave, lastUpdated: new Date().toISOString() }, null, 2)).toString("base64"),
      sha,
    });

    return NextResponse.json({ success: true });
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
