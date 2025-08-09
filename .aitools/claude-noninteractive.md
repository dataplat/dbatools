## **How to Use Anthropic's Claude Code Non-Interactively**

### **TL;DR**
Claude Code includes headless mode for non-interactive contexts like CI, pre-commit hooks, build scripts, and automation. Use the -p flag with a prompt to enable headless mode, and --output-format stream-json for streaming JSON output. The key is using the `-p` flag with proper tool permissions and output formatting for automated workflows.

## **Core Non-Interactive Setup**

### **Basic Syntax**
The basic pattern for non-interactive usage is: `claude -p "your prompt here"` This runs Claude Code in "print mode" where it executes once and exits, making it perfect for scripting and automation.

### **Essential Command Structure**
```bash
claude -p "your prompt" [options]
```

Common options include:
- `--output-format json|text|stream-json` - Control output format
- `--allowedTools "Tool1,Tool2"` - Pre-approve specific tools
- `--verbose` - Enable detailed logging for debugging
- `--max-turns N` - Limit conversation length for cost control
- `--system-prompt "prompt"` - Override default system instructions

## **Tool Permissions Management**

### **The Permission Challenge**
When using Claude CLI in non-interactive mode with the -p flag to run bash commands, Claude requests permission to use the Bash tool even though permissions are already configured. This is a known issue that requires specific workarounds.

### **Solutions for Tool Permissions**

**1. Use `--allowedTools` flag:**
```bash
claude -p "write hello world to test.txt" --allowedTools "Write,Edit"
```

**2. Configure project-level permissions:**
```bash
claude config add allowedTools "Write,Edit,Bash"
```

**3. For development workflows (use cautiously):**
```bash
claude --dangerously-skip-permissions -p "your prompt"
```

The --dangerously-skip-permissions flag completely disables Claude Code's permission system, granting unrestricted access to: File System Operations: Read, write, edit, and delete files without approval

## **Output Format Options**

### **Three Output Formats Available:**
Text - Human-readable plain text (default format). JSON - Structured data with metadata, analysis results, and processing information. Stream-JSON - Real-time streaming JSON for large responses and progressive processing.

**Examples:**
```bash
# JSON output for programmatic processing
claude -p "analyze code quality" --output-format json

# Stream JSON for real-time processing
claude -p "large analysis task" --output-format stream-json

# Text output (default)
claude -p "generate documentation" --output-format text
```

## **Advanced Non-Interactive Features**

### **Session Management**
```bash
# Resume previous session non-interactively
claude -p --resume session-id "continue with new prompt"

# Continue most recent session
claude -p --continue "add error handling"
```

### **Custom System Prompts**
You can provide custom system prompts to guide Claude's behavior: claude -p "Build a REST API" --system-prompt "You are a senior backend engineer. Focus on security, performance, and maintainability."

### **Input/Output Piping**
```bash
# Pipe data to Claude
cat logfile.txt | claude -p "analyze these logs for errors"

# Chain with other tools
claude -p "generate API docs" --output-format json | jq '.response'
```

## **MCP (Model Context Protocol) Integration**

### **Using MCP Servers Non-Interactively**
Important: MCP tools must be explicitly allowed using --allowedTools. MCP tool names follow the pattern mcp__<serverName>__<toolName>

```bash
claude -p "search for TODO comments" \
  --mcp-config mcp-servers.json \
  --allowedTools "mcp__filesystem__read_file,mcp__filesystem__list_directory"
```

## **Automation Examples**

### **CI/CD Integration**
```bash
# Security analysis in CI
claude -p "analyze this codebase for security vulnerabilities" \
  --allowedTools "Read,Bash" \
  --output-format json > security-report.json
```

### **Pre-commit Hook**
staged=$(git diff --cached --name-only --diff-filter=ACM)
payload=$(echo "$staged" | xargs cat)
analysis=$(echo "$payload" | claude -p "Review these changes for issues before commit" --allowedTools "View" --output-format json)

### **Log Analysis**
```bash
# Real-time log monitoring
tail -f app.log | claude -p "alert me if you see any anomalies in this log stream"
```

## **Cost Control and Performance**

### **Managing Costs**
The --max-turns flag helps control API costs by limiting conversation length.

```bash
# Limit conversation turns for cost control
claude --max-turns 3 -p "focused analysis task"
```

### **Performance Considerations**
Claude Code can be expensive: running a single mini project can cost up to $10, which adds up quickly for iterative or large-scale workflows. However, the average spend per user is $6/day on Claude Code compared to $20/mo for Cursor

## **Best Practices for Non-Interactive Usage**

### **1. Start Small and Scale Up**
And we'd also definitely recommend that you start small. So, like, test it on one test. Make sure that it has reasonable behavior. Iterate on your prompt. Then scale it up to 10.

### **2. Use Verbose Mode for Debugging**
For both of these use cases, it can be helpful to use the --verbose flag for debugging the Claude invocation. We generally recommend turning verbose mode off in production for cleaner output.

### **3. Security Considerations**
- Use minimal tool permissions (`--allowedTools "Read"` for analysis-only tasks)
- Avoid `--dangerously-skip-permissions` in production
- Keep ~/.claude.json private (chmod 600). Prefer environment variables for API keys over plain-text.

## **Common Issues and Solutions**

### **Permission Issues**
Claude Code ignores path patterns in allowedTools configuration when running in non-interactive mode - Use simple tool names without path patterns for better reliability.

### **Streaming Issues**
Claude Code CLI fails to send the required final {"type":"result",...} event in streaming JSON mode after successful tool execution, causing the process to hang indefinitely - This is a known bug that may require timeout handling in your automation.

## **Environment Variables**
```bash
# Disable telemetry for privacy
export DISABLE_TELEMETRY=1
export DISABLE_ERROR_REPORTING=1
export DISABLE_NON_ESSENTIAL_MODEL_CALLS=1

# API authentication
export ANTHROPIC_API_KEY="your-key-here"
```

## **SDK Integration**
The Claude Code SDK allows you to use Claude Code in non-interactive mode from your applications. It's available for TypeScript, Python, and command-line usage, enabling deeper integration into custom workflows and applications.

This comprehensive approach to non-interactive Claude Code usage enables powerful automation while maintaining security and cost control. Start with simple commands and gradually build more complex automated workflows as you become familiar with the tool's capabilities and limitations.