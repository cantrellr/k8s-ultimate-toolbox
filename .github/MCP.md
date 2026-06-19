# Model Context Protocol (MCP) Configuration

This repository is configured to use MCP servers with GitHub Copilot's Coding Agent to provide enhanced context and capabilities.

## Configured MCP Servers

### 1. GitHub Server
Provides access to GitHub repository data including issues, PRs, and repository information.

**Capabilities:**
- Read repository information
- Access issues and pull requests
- Query repository structure
- Read file contents

**Environment Variables:**
- `GITHUB_TOKEN` - Personal access token with repo scope

### 2. Filesystem Server
Provides access to the workspace filesystem for reading and analyzing files.

**Capabilities:**
- Read files from workspace
- List directory contents
- Search for files
- Access file metadata

**Scope:**
- Limited to `${workspaceFolder}` (this repository)

### 3. Kubernetes Server
Provides Kubernetes cluster access for testing and validation.

**Capabilities:**
- Query cluster resources
- Read pod logs
- Get resource status
- Execute commands in pods

**Environment Variables:**
- `KUBECONFIG` - Path to kubeconfig file

## Setup Instructions

### Prerequisites

1. **Node.js and npm** installed
2. **GitHub Personal Access Token** with `repo` scope
3. **kubectl** configured (for Kubernetes server)

### Configuration

1. **Set Environment Variables:**

```bash
# Add to your shell profile (~/.bashrc, ~/.zshrc, etc.)
export GITHUB_TOKEN="ghp_your_token_here"
export KUBECONFIG="${HOME}/.kube/config"
```

2. **Verify MCP Servers:**

```bash
# Test GitHub server
npx -y @modelcontextprotocol/server-github --help

# Test Filesystem server
npx -y @modelcontextprotocol/server-filesystem --help

# Test Kubernetes server
npx -y @modelcontextprotocol/server-kubernetes --help
```

3. **GitHub Copilot Integration:**

The `.github/copilot-mcp.json` file is automatically detected by GitHub Copilot when using the Coding Agent in this repository.

## Usage with Copilot Coding Agent

When working with the Coding Agent, it can now:

- **Access GitHub data** - Query issues, PRs, and repository structure
- **Read workspace files** - Analyze Helm charts, Dockerfiles, scripts
- **Validate against Kubernetes** - Test deployments, check cluster state

### Example Scenarios

1. **Analyze Issues:**
   - "Review all open issues and suggest which ones to prioritize"
   - "Check if there are any security-related issues"

2. **Validate Helm Chart:**
   - "Read the Helm chart and validate against best practices"
   - "Check if the chart templates are syntactically correct"

3. **Test Deployment:**
   - "Deploy the chart to my cluster and verify it works"
   - "Check the status of pods in the toolbox namespace"

## Security Considerations

- **GitHub Token:** Store securely, use minimal required scopes (repo)
- **Filesystem Access:** Limited to workspace folder only
- **Kubernetes Access:** Uses existing kubeconfig permissions
- **Token Rotation:** Regularly rotate GitHub personal access tokens
- **No Hardcoded Secrets:** All credentials via environment variables

## Troubleshooting

### GitHub Server Not Working

```bash
# Verify token is set
echo $GITHUB_TOKEN

# Test manually
npx -y @modelcontextprotocol/server-github
```

### Kubernetes Server Issues

```bash
# Verify kubeconfig
kubectl cluster-info

# Check permissions
kubectl auth can-i get pods --all-namespaces
```

### Filesystem Access Denied

Ensure the MCP server has access to the workspace directory and is not blocked by security software.

## References

- [MCP Documentation](https://modelcontextprotocol.io)
- [GitHub Copilot with MCP](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/extend-coding-agent-with-mcp)
- [MCP Server GitHub](https://github.com/modelcontextprotocol/servers/tree/main/src/github)
- [MCP Server Filesystem](https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem)
- [MCP Server Kubernetes](https://github.com/modelcontextprotocol/servers/tree/main/src/kubernetes)

## Contributing

When adding new MCP servers:

1. Update `.github/copilot-mcp.json`
2. Document the server in this README
3. Add setup instructions
4. Test with the Coding Agent
5. Submit a PR

---

*Part of the Ultimate K8s Toolbox project - "First Flight" v1.0.2*
