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

$assemblyPath = Join-Path -Path $PSScriptRoot -ChildPath "$editionFolder\dbatools.agent.dll"
if (-not (Test-Path -Path $assemblyPath)) {
    # Dev-staging fallback: the flip preflight also stages a flat copy at the module root
    $assemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'dbatools.agent.dll'
}

$assemblyModule = Import-Module -Name $assemblyPath -PassThru

# The dll import above makes its cmdlets NESTED members of this script module; without an
# explicit re-export they never surface - most visibly on PS 3/4, where the manifest cannot
# compensate. The wildcard here is safe because the manifest's explicit CmdletsToExport list
# (maintained by the flip tool) is the authoritative filter that auto-loading reads.
Export-ModuleMember -Cmdlet *

# TEPP bridge (P0-012): register this module's OWN Database-domain completer mappings.
# Single-owner rule (specs/modules.md, contracts section 2): a satellite maps only the commands
# it exports and never another module's. The "database" TEPP scriptblock and its instance cache
# builder stay owned by the root dbatools module (private/dynamicparams/database.ps1) - this
# block only points this module's -Database parameters at that shared domain.
# The mapping must come from the imported assembly rather than Get-Command -Module, because the
# nested dll's cmdlets are not discoverable under this module's name while the psm1 is still
# executing.
# PS 3/4 have no Register-ArgumentCompleter, so they stay completion-free and warning-clean.
if (($PSVersionTable.PSVersion.Major -ge 5) -and (Get-Command -Name Register-ArgumentCompleter -ErrorAction SilentlyContinue)) {
    $teppScriptBlock = {
        param (
            $commandName,
            $parameterName,
            $wordToComplete,
            $commandAst,
            $fakeBoundParameter
        )

        if ($teppScript = [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::GetTeppScript($commandName, $parameterName)) {
            $start = Get-Date
            $teppScript.LastExecution = $start
            $teppScript.LastDuration = New-Object System.TimeSpan(-1) # Null it, just in case. It's a new start.

            try {
                $ExecutionContext.InvokeCommand.InvokeScript($true, ([System.Management.Automation.ScriptBlock]::Create($teppScript.ScriptBlock.ToString())), $null, @($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter))
            } catch {
                $null = 1
            }

            $teppScript.LastDuration = (Get-Date) - $start
        }
    }

    $teppCommandName = @()
    foreach ($teppCmdlet in $assemblyModule.ExportedCmdlets.Values) {
        if ($teppCmdlet.Parameters.ContainsKey("Database")) {
            $teppCommandName += $teppCmdlet.Name
            [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::AddTabCompletionSet($teppCmdlet.Name, "Database", "database")
        }
    }

    if ($teppCommandName.Count -gt 0) {
        $splatTeppCompleter = @{
            CommandName   = $teppCommandName
            ParameterName = "Database"
            ScriptBlock   = $teppScriptBlock
        }
        Register-ArgumentCompleter @splatTeppCompleter
    }
}
