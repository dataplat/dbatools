param($ModuleName = 'dbatools')

Describe "Test-DbaDbRecoveryModel Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDbRecoveryModel
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.Object[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have RecoveryModel as a parameter" {
            $CommandUnderTest | Should -HaveParameter RecoveryModel -Type System.Object
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }
}

Describe "Test-DbaDbRecoveryModel Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $fullRecovery = "dbatoolsci_RecoveryModelFull"
        $bulkLoggedRecovery = "dbatoolsci_RecoveryModelBulk"
        $simpleRecovery = "dbatoolsci_RecoveryModelSimple"
        $psudoSimpleRecovery = "dbatoolsci_RecoveryModelPsudoSimple"
        $server = Connect-DbaInstance -SqlInstance $global:instance2

        Stop-DbaProcess -SqlInstance $global:instance2 -Database model
        $server.Query("CREATE DATABASE $fullRecovery")
        Stop-DbaProcess -SqlInstance $global:instance2 -Database model
        $server.Query("CREATE DATABASE $bulkLoggedRecovery")
        Stop-DbaProcess -SqlInstance $global:instance2 -Database model
        $server.Query("CREATE DATABASE $simpleRecovery")
        Stop-DbaProcess -SqlInstance $global:instance2 -Database model
        $server.Query("CREATE DATABASE $psudoSimpleRecovery")

        Set-DbaDbRecoveryModel -sqlInstance $global:instance2 -RecoveryModel BulkLogged -Database $bulkLoggedRecovery -Confirm:$false
        Set-DbaDbRecoveryModel -SqlInstance $global:instance2 -RecoveryModel Simple -Database $simpleRecovery -Confirm:$false
        Set-DbaDbRecoveryModel -SqlInstance $global:instance2 -RecoveryModel Simple -Database $psudoSimpleRecovery -Confirm:$false
        Set-DbaDbRecoveryModel -SqlInstance $global:instance2 -RecoveryModel Full -Database $psudoSimpleRecovery -Confirm:$false
    }

    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance2 -Database $fullRecovery, $bulkLoggedRecovery, $simpleRecovery, $psudoSimpleRecovery
    }

    Context "Default Execution" {
        BeforeAll {
            $results = Test-DbaDbRecoveryModel -SqlInstance $global:instance2 -Database $fullRecovery, $psudoSimpleRecovery, 'Model'
        }

        It "Should return $fullRecovery, $psudoSimpleRecovery, and Model" {
            $results.Database | Should -BeIn ($fullRecovery, $psudoSimpleRecovery, 'Model')
        }
    }

    Context "Full Recovery" {
        BeforeAll {
            $results = Test-DbaDbRecoveryModel -SqlInstance $global:instance2 -RecoveryModel Full -Database $fullRecovery, $psudoSimpleRecovery -ExcludeDatabase 'Model'
        }

        It "Should return $fullRecovery and $psudoSimpleRecovery" {
            $results.Database | Should -BeIn ($fullRecovery, $psudoSimpleRecovery)
        }
    }

    Context "Bulk Logged Recovery" {
        BeforeAll {
            $results = Test-DbaDbRecoveryModel -SqlInstance $global:instance2 -RecoveryModel Bulk_Logged -Database $bulkLoggedRecovery
        }

        It "Should return $bulkLoggedRecovery" {
            $results.Database | Should -Be $bulkLoggedRecovery
        }
    }

    Context "Simple Recovery" {
        BeforeAll {
            $results = Test-DbaDbRecoveryModel -SqlInstance $global:instance2 -RecoveryModel Simple -Database $simpleRecovery
        }

        It "Should return $simpleRecovery" {
            $results.Database | Should -Be $simpleRecovery
        }
    }

    Context "Psudo Simple Recovery" {
        BeforeAll {
            $results = Test-DbaDbRecoveryModel -SqlInstance $global:instance2 -RecoveryModel Full | Where-Object {$_.database -eq $psudoSimpleRecovery}
        }

        It "Should return $psudoSimpleRecovery" {
            $results.Database | Should -Be $psudoSimpleRecovery
        }
    }

    Context "Error Check" {
        It "Should Throw Error for Incorrect Recovery Model" {
            { Test-DbaDbRecoveryModel -SqlInstance $global:instance2 -RecoveryModel Awesome -EnableException -Database 'dontexist' } | Should -Throw
        }

        It "Should Throw Error for a DB Connection Error" {
            Mock Connect-DbaInstance { throw } -ModuleName dbatools
            { Test-DbaDbRecoveryModel -SqlInstance $global:instance2 -EnableException } | Should -Throw
        }

        It "Should Throw Error for Output Error" {
            Mock Select-DefaultView { throw } -ModuleName dbatools
            { Test-DbaDbRecoveryModel -SqlInstance $global:instance2 -EnableException } | Should -Throw
        }
    }
}
