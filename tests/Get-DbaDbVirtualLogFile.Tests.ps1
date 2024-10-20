param($ModuleName = 'dbatools')

Describe "Get-DbaDbVirtualLogFile Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbVirtualLogFile
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "ExcludeDatabase",
            "IncludeSystemDBs",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Get-DbaDbVirtualLogFile Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $db1 = "dbatoolsci_getvlf"
        $server.Query("CREATE DATABASE $db1")
        $needed = Get-DbaDatabase -SqlInstance $global:instance2 -Database $db1
        $setupright = $true
        if ($needed.Count -ne 1) {
            $setupright = $false
            Set-ItResult -Inconclusive -Because "Setup failed"
        }
    }

    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database $db1
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaDbVirtualLogFile -SqlInstance $global:instance2 -Database $db1
        }

        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Database,RecoveryUnitId,FileId,FileSize,StartOffset,FSeqNo,Status,Parity,CreateLSN'.Split(',')
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should have database name of $db1" {
            $results | ForEach-Object {
                $_.Database | Should -Be $db1
            }
        }
    }
}
