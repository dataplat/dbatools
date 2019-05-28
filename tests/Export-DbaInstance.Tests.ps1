$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'Path', 'FilePath', 'NoRecovery', 'IncludeDbMasterKey', 'Exclude', 'BatchSeparator', 'ScriptingOption', 'Append', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    AfterAll {
        $timenow = (Get-Date -uformat "%m%d%Y%H")
        $ExportedItems = Get-ChildItem "$($env:USERPROFILE)\Documents" -Recurse | Where-Object { $_.Name -match "-$timenow\d{4}" -and $_.Attributes -eq 'Directory' }
        $null = Remove-Item -Path $($ExportedItems.FullName) -Force -Recurse -ErrorAction SilentlyContinue
    }

    Context "Should Export all items from an instance" {
        $results = Export-DbaInstance -SqlInstance $script:instance2
        It "Should execute with default settings" {
            $results | Should Not Be Null
        }
    }
    Context "Should exclude some items from an Export" {
        $results = Export-DbaInstance -SqlInstance $script:instance2 -Exclude Databases, Logins, SysDbUserObjects, ReplicationSettings
        It "Should execute with parameters excluding objects" {
            $results | Should Not Be Null
        }
    }
}