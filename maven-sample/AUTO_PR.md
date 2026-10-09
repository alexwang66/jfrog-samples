# Maven Auto-PR Demo

本示例使用 GitHub Actions 和 Frogbot v3，从 JFrog Xray 的漏洞详情直接创建依赖升级 Pull Request。

工作流位于仓库根目录的 [`.github/workflows/maven-auto-pr.yml`](../.github/workflows/maven-auto-pr.yml)。GitHub 只识别仓库根目录下的 `.github/workflows`，因此工作流不能放在 `maven-sample/.github/workflows`。Frogbot 会递归发现本目录的 `pom.xml`。

## 前置条件

- JFrog Platform 具备 Unified License，以及 Advanced Security 和 Curation 权限。
- Frogbot 版本不低于 3.6.0，Xray 版本为 3.153.x 或更高兼容版本。
- 源码仓库托管在 GitHub.com，并已在所属 GitHub Organization 安装 JFrog GitHub App。
- 漏洞组件是 `pom.xml` 中的直接依赖，并且 Xray 提供可修复版本。
- 制品通过 JFrog CLI 上传并发布 Build Info；Build Info 必须包含 Git URL、分支和提交号。

## GitHub 配置

在仓库的 **Settings > Secrets and variables > Actions** 中配置：

| 类型 | 名称 | 用途 |
| --- | --- | --- |
| Repository variable | `JFROG_URL_SOLENG_LATEST` | Auto-PR 使用的 Soleng Latest JFrog Platform 根地址 |
| Repository secret | `SOLENG_LATEST_TOKEN` | Frogbot 访问 Soleng Latest 的 Token |

工作流将这两个仓库配置映射为 Frogbot 所需的 `JF_URL` 和 `JF_ACCESS_TOKEN` 环境变量，确保 URL 与 Token 来自同一个 JFrog Platform 实例。

不需要创建 `GITHUB_TOKEN` Secret。GitHub 会自动提供该 Token，工作流已声明 `contents: write` 和 `pull-requests: write` 权限。还需在 **Settings > Actions > General** 中启用 **Allow GitHub Actions to create and approve pull requests**。

## 运行 Demo

### 从 Xray 触发

1. 运行 `Build And Deploy Runtime Sample` GitHub Actions，发布 `maven-sample` 制品及包含 Git 信息的 Build Info。
2. 确认目标 Artifactory 仓库已被 Xray 索引。
3. 在 JFrog Platform 打开 **Application > Xray > Scans List > Repositories**。
4. 选择本示例制品及版本，进入 **Security Issues > Vulnerabilities**。
5. 选择具有 Direct 修复版本的漏洞，在 **Remediation** 中点击 **Create Pull Request**。

Xray 会发送类型为 `jfrog-auto-pr` 的 `repository_dispatch` 事件。工作流会读取官方 payload 字段 `component_name`、`affected_version`、`fix_version`、`branch` 和 `commit_hash`，然后由 Frogbot 修改 `maven-sample/pom.xml` 并创建 PR。

### 手动验证工作流

在 GitHub Actions 中选择 **Maven Frogbot Auto-PR**，点击 **Run workflow**。可以使用当前直接依赖验证参数传递：

- `component-name`: `com.alibaba:fastjson`
- `affected-version`: `1.2.83`
- `fix-version`: 使用 Xray Remediation 给出的修复版本
- `branch-name`: 通常填写 `main`，留空则使用默认分支
- `commit-hash`: 可选；如填写，工作流仍会以 `branch-name` 或默认分支作为 PR 目标分支

> 手动填写的修复版本应来自 Xray 的 Remediation 结果。Auto-PR 只处理直接依赖；传递依赖不会被自动修改。

## 常见问题

- **Create Pull Request 不可用**：通常是制品缺少 Git/VCS 信息、JFrog GitHub App 未安装、组件不是直接依赖，或没有可用修复版本。
- **工作流未启动**：确认事件类型是 `jfrog-auto-pr`，且工作流文件已存在于目标分支。
- **Frogbot 找不到组件**：Maven 组件名使用 `groupId:artifactId`，版本必须与 `pom.xml` 和扫描结果一致。
- **PR 创建失败**：确认 Actions 允许创建 PR；若组织策略禁止 `GITHUB_TOKEN` 创建 PR，请按组织策略使用具有 Contents 和 Pull requests 写权限的细粒度 Token，并将工作流中的 `JF_GIT_TOKEN` 改为相应 Secret。

参考：[JFrog Auto-PR 官方文档](https://docs.jfrog.com/security/docs/how-to-create-fix-pull-requests-with-auto-pr)
