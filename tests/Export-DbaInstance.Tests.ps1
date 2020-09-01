$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'Path', 'NoRecovery', 'IncludeDbMasterKey', 'Exclude', 'BatchSeparator', 'ScriptingOption', 'NoPrefix', 'ExcludePassword', 'Append', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    AfterAll {
        $null = Remove-Item -Path $script:results -Force -Recurse -ErrorAction SilentlyContinue
    }

    Context "Should exclude some items from an Export" {
        $script:results = Export-DbaInstance -SqlInstance $script:instance2 -Exclude Databases, Logins, SysDbUserObjects, ReplicationSettings, ResourceGovernor
        It "Should execute with parameters excluding objects" {
            $script:results | Should Not Be Null
        }
    }
}