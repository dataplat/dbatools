$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'InputObject', 'ScriptingOptionsObject', 'Path', 'FilePath', 'Encoding', 'BatchSeparator', 'NoPrefix', 'Passthru', 'NoClobber', 'Append', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "works as expected" {

        It "should export some text matching create table" {
            $results = Get-DbaDbTable -SqlInstance $script:instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru
            $results -match "CREATE TABLE"
        }
        It "should include BatchSeparator based on the Formatting.BatchSeparator configuration" {
            $results = Get-DbaDbTable -SqlInstance $script:instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru
            $results -match "(Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator')"
        }

        It "should include the defined BatchSeparator" {
            $results = Get-DbaDbTable -SqlInstance $script:instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru -BatchSeparator "MakeItSo"
            $results -match "MakeItSo"
        }

        It "should not accept non-SMO objects" {
            $results = Get-DbaDbTable -SqlInstance $script:instance2 -Database msdb | Select-Object -First 1 | Export-DbaScript -Passthru -BatchSeparator "MakeItSo"
            $null = [pscustomobject]@{ Invalid = $true } | Export-DbaScript -WarningVariable invalid -WarningAction Continue
            $invalid -match "not a SQL Management Object"
        }
    }
}