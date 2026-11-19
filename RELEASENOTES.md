# Release notes

## Native commands: breaking changes

Many commands now run as native C# cmdlets from dbatools.library. Run
`Get-Help about_dbatools_native` for details.

### Explicit -Debug on PowerShell 7

Native commands write messages through PowerShell's public stream APIs. On
PowerShell 7, passing `-Debug` explicitly to a native command changes what you
see:

- a warning or verbose message may ask for confirmation before the command
  continues;
- verbose messages may appear without `-Verbose`;
- a warning that dbatools would otherwise suppress, such as the one that
  accompanies a terminating error under `-EnableException`, may become visible.

Noninteractive callers (scheduled tasks, agent jobs, CI pipelines, remote
sessions) should omit explicit `-Debug` when they cannot answer these prompts.
Setting `$DebugPreference = 'Continue'` while still passing `-Debug` does not
reliably prevent them. Behavior without explicit `-Debug` is unchanged,
including logs, error records and preference restoration. The measured
comparison found no Windows PowerShell 5.1 differences in the cases it covered.

### Legacy script message transforms and events

- Normal import fills new typed native registries
  (`MessageHost.NativeTargetTransforms`, `NativeExceptionTransforms`,
  `NativeTargetTransformList`, `NativeExceptionTransformList`) with the
  built-in defaults. Native commands never run scriptblocks.
- The script registries used by `Register-DbaMessageTransform`
  (`TargetTransforms`, `ExceptionTransforms`, `TargetTransformList`,
  `ExceptionTransformList`) now start empty. Their counts, value types and
  default entries have changed, and clearing them no longer clears native
  defaults.
- When a legacy script transform matches, a native command throws
  `NotSupportedException` naming the transform kind, type, function and
  module. Remove the matching legacy registration to resume native processing.
- Native commands still log messages but do not run `Register-DbaMessageEvent`
  scripts. Each matching subscription produces the nonterminating error
  `NativeMessageEventNotSupported` (category `InvalidOperation`, target: the
  subscription name).
- Script transforms and events keep working only on the unfinished legacy
  `Write-Message` frontend.
