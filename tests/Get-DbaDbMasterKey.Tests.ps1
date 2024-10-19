param($ModuleName = 'dbatools')

Describe "Get-DbaDbMasterKey Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbMasterKey
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

Describe "Get-DbaDbMasterKey Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $global:instance1
        $null = $server.Query("Create Database [$dbname]")
        $null = New-DbaDbMasterKey -SqlInstance $global:instance1 -Database $dbname -Password (ConvertTo-SecureString -AsPlainText -Force -String 'ThisIsAPassword!') -Confirm:$false
    }
    AfterAll {
        Remove-DbaDbMasterKey -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
        Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
    }

    Context "Gets DbMasterKey" {
        BeforeAll {
            $results = Get-DbaDbMasterKey -SqlInstance $global:instance1 | Where-Object {$_.Database -eq "$dbname"}
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should be the key on $dbname" {
            $results.Database | Should -Be $dbname
        }
        It "Should be encrypted by the server" {
            $results.isEncryptedByServer | Should -BeTrue
        }
    }

    Context "Gets DbMasterKey when using -database" {
        BeforeAll {
            $results = Get-DbaDbMasterKey -SqlInstance $global:instance1 -Database $dbname
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should be the key on $dbname" {
            $results.Database | Should -Be $dbname
        }
        It "Should be encrypted by the server" {
            $results.isEncryptedByServer | Should -BeTrue
        }
    }

    Context "Gets no DbMasterKey when using -ExcludeDatabase" {
        BeforeAll {
            $results = Get-DbaDbMasterKey -SqlInstance $global:instance1 -ExcludeDatabase $dbname
        }
        It "Gets no results" {
            $results | Should -BeNullOrEmpty
        }
    }
}
