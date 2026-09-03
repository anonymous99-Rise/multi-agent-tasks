const fs = require('fs');
const path = require('path');

const agentsJson = process.argv[2] || path.join(__dirname, '..', 'agents.json');
const tokenVar = process.env.TOKEN_VAR || 'TOKEN';

const data = JSON.parse(fs.readFileSync(agentsJson, 'utf8'));
const agents = data.agents.filter(a => a.role !== 'commander');

console.log('==========================================');
console.log('Multi-Agent Cron 配置生成器');
console.log('==========================================');
console.log('');
console.log('# 使用前先初始化环境:');
console.log('#   source scripts/init_env.sh [openclaw|hermes]');
console.log('');

agents.forEach(agent => {
  const name = agent.name;
  const slug = agent.slug;
  const framework = agent.framework;
  const role = agent.role;
  const tgUsername = agent.tgUsername || '';

  console.log('-------------------------------------------');
  console.log('Agent:', name, '(' + slug + ')');
  console.log('Framework:', framework);
  console.log('Role:', role);
  if (tgUsername) {
    console.log('Telegram:', '@' + tgUsername);
  }
  console.log('');

  if (framework === 'openclaw') {
    console.log('# OpenClaw cron:');
    console.log('openclaw cron add \\');
    console.log('  --name "' + name + '" \\');
    console.log('  --cron "*/5 * * * *" \\');
    console.log('  --session isolated \\');
    console.log('  --message "source $MAT_ROOT/scripts/init_env.sh ' + framework + ' && cd $MAT_ROOT && bash scripts/inbox_processor.sh \\"$' + tokenVar + '\\" \\"' + slug + '\\"" \\');
    if (tgUsername) {
      console.log('  --announce --channel telegram --to "@' + tgUsername + '"');
    } else {
      console.log('  # 注意: 未配置 tgUsername，请在 agents.json 中设置');
    }
  } else if (framework === 'hermes') {
    console.log('# Hermes cron:');
    console.log('hermes cron add \\');
    console.log('  --name "' + name + '" \\');
    console.log('  --cron "*/5 * * * *" \\');
    console.log('  --command "source $MAT_ROOT/scripts/init_env.sh ' + framework + ' && cd $MAT_ROOT && bash scripts/inbox_processor.sh \\"$' + tokenVar + '\\" \\"' + slug + '\\""');
  } else {
    console.log('# Unknown framework:', framework);
    console.log('# 请手动配置', name, '的 cron');
  }
  console.log('');
});

console.log('==========================================');
console.log('复制上面的命令到你的框架中执行');
console.log('==========================================');
console.log('');
console.log('提示:');
console.log('  - MAT_ROOT 会在 init_env.sh 后自动设置');
console.log('  - 确保 $' + tokenVar + ' 环境变量已设置');
console.log('==========================================');
