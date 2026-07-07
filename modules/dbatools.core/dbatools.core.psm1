# Thin shim loader (migration/specs/modules.md section 5.3). Its only jobs: import the
# edition-appropriate packaged cmdlet assembly and register this module's own TEPP completer
# mappings. Assembly redirectors and shared-assembly loading belong to dbatools.library,
# which the manifest's RequiredModules chain has already loaded - DO NOT be tempted to load
# SQL Server assemblies here.
if ($PSVersionTable.PSEdition -eq 'Core') {
    $editionFolder = 'core'
} else {
    $editionFolder = 'desktop'
}

$assemblyPath = Join-Path -Path $PSScriptRoot -ChildPath "$editionFolder\dbatools.core.dll"
if (-not (Test-Path -Path $assemblyPath)) {
    # Dev-staging fallback: the flip preflight also stages a flat copy at the module root
    $assemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'dbatools.core.dll'
}

Import-Module -Name $assemblyPath

# The dll import above makes its cmdlets NESTED members of this script module; without an
# explicit re-export they never surface - most visibly on PS 3/4, where the manifest cannot
# compensate. The wildcard here is safe because the manifest's explicit CmdletsToExport list
# (maintained by the flip tool) is the authoritative filter that auto-loading reads.
Export-ModuleMember -Cmdlet *

# Command shortcut aliases owned by this module's commands (BP-604): class-level [Alias] is
# banned on the net472 floor, so the owning satellite registers Set-Alias plus an explicit
# AliasesToExport entry in the manifest.
Set-Alias -Name cdi -Value Connect-DbaInstance
Export-ModuleMember -Alias cdi

# TEPP completer registration for this module's commands arrives with the TEPP bridge (P0-012);
# PS 3/4 must stay completion-free and warning-clean, so nothing is registered before then.
