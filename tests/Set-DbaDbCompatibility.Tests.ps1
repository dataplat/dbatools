$CommandName = $MyInvocation.MyCommand.Name.Replace('.Tests.ps1', '')
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('WhatIf', 'Confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Compatibility', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It 'Should only contain our specific parameters' {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag 'IntegrationTests' {
    BeforeAll {
        $sqlCn = Connect-DbaInstance -SqlInstance $script:instance1
        $sqlCn.Refresh()
        $dbNameNotMatches = "dbatoolscliCompatibilityLevelNotMatch_$(Get-Random -Minimum 600 -Maximum 1100)"
        $instanceLevel = $sqlCn.Databases['master'].CompatibilityLevel
        <# create a database that is one level down from instance level, any version tested against supports the prior level #>
        $previousCompatLevel = [int]($instanceLevel.ToString().Trim('Version')) - 10
        #$queryNot = "CREATE DATABASE $dbNameNotMatches"
        $null = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbNameNotMatches
        #$sqlCn.Query($queryNot)
        $queryAlter = "ALTER DATABASE $dbNameNotMatches SET COMPATIBILITY_LEVEL = $($previousCompatLevel)"
        $sqlCn.Query($queryAlter)

        $sqlCn.Refresh()
        $sqlCn.Databases.Refresh()
        $resultMatches = Set-DbaDbCompatibility -SqlInstance $sqlCn -Database 'master' -Verbose 4>&1
        $verboseMsg = '*current Compatibility Level matches instance level*'

        $sqlCn.Refresh()
        $sqlCn.Databases.Refresh()
        $resultNotMatches = Set-DbaDbCompatibility -SqlInstance $sqlCn -Database $dbNameNotMatches -Verbose 4>&1
        $verboseSetMsg = '*Performing the operation "Setting*Compatibility Level*'
    }
    AfterAll {
        $sqlCn = Connect-DbaInstance -SqlInstance $script:instance1
        Remove-DbaDatabase -SqlInstance $sqlCn -Database $dbNameNotMatches -Confirm:$false
        $sqlCn.ConnectionContext.Disconnect()
    }
    Context 'Instance Compatibility Level' {
        It 'Detects database is already at the instance level' {
            $resultMatches[-1] | Should -BeLike $verboseMsg
        }
        It 'Should have no output' {
            ($resultMatches | Get-Member | Select-Object TypeName -Unique).Count | Should -BeExactly 1
        }
    }
    Context 'Providing Compatibility Level' {
        It 'Performs operation to update compatibility level' {
            $resultNotMatches[-2] | Should -BeLike $verboseSetMsg
        }
        It 'Should output an object' {
            ($resultNotMatches | Get-Member | Select-Object TypeName -Unique).Count | Should -BeExactly 2
        }
    }
}