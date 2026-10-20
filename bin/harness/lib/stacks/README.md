# Stack adapters

> WRITTEN BY: the template (the onboarding may add an adapter). BUDGET: 90 lines.

A stack adapter tells the harness how to handle a tool that must **live outside the coder's
turn**. Most projects do not need one: with `STACK=none` (the default) the coder runs its build,
tests and app itself, inside its turn, and the gate runs `GATE_CMDS`.

## When a project needs one

- A **long-running editor** the agents drive through MCP (Unreal Editor, Godot editor, Unity):
  it must be started before the coder, restarted after a crash, and its crash log fed back.
- An **emulator or simulator** (Android emulator, iOS simulator) that takes minutes to boot.
- A **dev server** (web app with hot reload) that the coder and the captures share.
- Processes built by the stack that `stop-all.ps1` must find and kill (game exe, server).

If none of these apply, keep `STACK=none`. No adapter is shipped with the template.

## How it is loaded

`config/project.env`: `STACK=<name>` -> `bin/harness/lib/stacks/<name>.ps1`, dot-sourced only
if the file exists. Every harness script does, at SCRIPT level (a dot-source inside a function
would only live inside that function):

```powershell
. (Join-Path $PSScriptRoot "lib\common.ps1")
$StackLib = Get-StackLib; if ($StackLib) { . $StackLib }
```

The adapter is loaded AFTER `common.ps1`: it can use `$Root`, `$Cfg`, `$State`, `$Logs`,
`Note`, `Read-Utf8`, ... and it replaces the defaults below. Add its own keys to
`config/project.env` (e.g. `EDITOR_EXE`, `MCP_PORT`) and read them with `$Cfg["KEY"]`.

## The interface (defaults in `common.ps1` = no stack)

| Member | Called by | Returns | Default |
|---|---|---|---|
| `Start-Stack` | run-coder, before the coder | `$true` if ready (`$false` = infrastructure failure, retried) | `$true` |
| `Get-StackCrashNote` | run-coder, on resume | text about a recent crash, injected in the prompt | `""` |
| `Get-StackMcp` | `New-CoderMcp` | MCP server names (in `.mcp.json`) ALWAYS given to the coder | `@()` |
| `Get-StackHealth` | health.ps1 | lines `@(state, text)`, state `"OK "`, `"KO "` or `"?? "` | `@()` |
| `Get-AppProcesses` | stop-all, health | processes built/run by the project | processes named `PROJECT` |
| `Stop-StackActivity` | stop-all | stops what runs INSIDE the editor (play mode, ticks); returns what was stopped | `""` |
| `Stop-StackEditor` | stop-all `-Editor` | editor pids to kill | `@()` |
| `$StackKillPatterns` | stop-all | regexes on command lines to kill | `@()` |

Rules: an adapter never prints when loaded (scripts are read as JSON), never blocks for long
(`Start-Stack` waits with a bounded loop), and treats a missing tool as NOT FATAL when a task
can progress without it (a docs task does not need the editor).

## Lessons (from a real editor adapter)

- Ping an MCP endpoint with a POST, never a GET: a GET opens an SSE stream that never closes.
- A crashed editor keeps its port; crash-report helpers inherit it and block the next bind:
  kill them, and check that nothing survives before restarting.
- Start the editor unattended and muted: a modal dialog freezes the main thread (and MCP);
  agents never play sound.
- Boot time grows with the project: wait long (bounded) before concluding it failed.

## Skeleton

```powershell
# EDITOR X, seen from the harness - dot-sourced AFTER common.ps1 when STACK=editorx.
$EditorExe = $Cfg["EDITOR_EXE"]
$StackKillPatterns = @('editorx\.exe')

function Test-EditorAlive { return [bool](Get-Process -Name editorx -ErrorAction SilentlyContinue) }

function Start-Stack {
    if (Test-EditorAlive) { return $true }
    if (-not $EditorExe -or -not (Test-Path $EditorExe)) { Note "(editor not found: config EDITOR_EXE)"; return $true }
    Start-Process -FilePath $EditorExe -ArgumentList @("--headless-safe") | Out-Null
    for ($k = 0; $k -lt 120; $k++) { Start-Sleep -Seconds 5; if (Test-EditorAlive) { Note "editor ready"; return $true } }
    return $false
}
function Get-StackMcp { return @("editorx") }
function Get-StackHealth {
    if (Test-EditorAlive) { return ,@("OK ", "editor running") }
    return ,@("?? ", "editor not running")
}
function Stop-StackEditor { return @(Get-Process -Name editorx -ErrorAction SilentlyContinue | ForEach-Object { $_.Id }) }
```
