$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig
. "$PSScriptRoot\..\private\functions\Invoke-TlsWebRequest"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'LocalFile', 'Database', 'EnableException', 'Force'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $dbName = "WhoIsActive-$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $dbName
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName -Confirm:$false
    }

    Context "Should install sp_WhoIsActive" {
        BeforeAll {
            $results = Install-DbaWhoIsActive -SqlInstance $TestConfig.instance1 -Database $dbName
        }

        It "Should output correct results" {
            $results.Database | Should -Be $dbName
            $results.Name | Should -Be "sp_WhoisActive"
            $results.Status | Should -Be "Installed"
        }
    }

    Context "Should update sp_WhoIsActive" {
        BeforeAll {
            $results = Install-DbaWhoIsActive -SqlInstance $TestConfig.instance1 -Database $dbName
        }

        It "Should output correct results" {
            $results.Database | Should -Be $dbName
            $results.Name | Should -Be "sp_WhoisActive"
            $results.Status | Should -Be "Updated"
        }
    }
}
