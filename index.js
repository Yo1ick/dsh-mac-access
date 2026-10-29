// dsh-mac-access — Windows 访问 Mac DSH 链路管理插件
// 只注册一个 runtime skill（mac-access）；运维动作全部由随包 tools/mac-access.sh 完成，
// skill 正文指导 agent 调用它。插件本身无后台常驻逻辑。
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const name = 'dsh-mac-access';

export function apply(ctx, config = {}) {
  const skillPath = fileURLToPath(new URL('./skill.md', import.meta.url));
  const defaultTools = fileURLToPath(new URL('./tools/mac-access.sh', import.meta.url));
  const toolsPath = typeof config.toolsPath === 'string' && config.toolsPath ? config.toolsPath : defaultTools;

  const content = readFileSync(skillPath, 'utf8').replaceAll('__TOOLS_PATH__', toolsPath);

  return ctx.skills.register({
    name: 'mac-access',
    source: 'bundled',
    description:
      '管理 Windows 访问 Mac DSH 的跨机链路：一键体检（check）、把最新登录 URL 推给 Windows（push）、部署/修复 Windows 一键脚本与桌面快捷方式（win-setup）。',
    whenToUse:
      '用户提到 Windows 访问 Mac DSH、token 过期、打开 Mac DSH 的脚本或快捷方式、链路不通/要体检时调用。',
    content,
  });
}
