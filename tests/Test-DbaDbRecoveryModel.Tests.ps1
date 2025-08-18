#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDbRecoveryModel",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Database",
                "ExcludeDatabase",
                "SqlCredential",
                "RecoveryModel",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $fullRecovery = "dbatoolsci_RecoveryModelFull"
        $bulkLoggedRecovery = "dbatoolsci_RecoveryModelBulk"
        $simpleRecovery = "dbatoolsci_RecoveryModelSimple"
        $psudoSimpleRecovery = "dbatoolsci_RecoveryModelPsudoSimple"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        Stop-DbaProcess -SqlInstance $TestConfig.instance2 -Database model
        $server.Query("CREATE DATABASE $fullRecovery")
        Stop-DbaProcess -SqlInstance $TestConfig.instance2 -Database model
        $server.Query("CREATE DATABASE $bulkLoggedRecovery")
        Stop-DbaProcess -SqlInstance $TestConfig.instance2 -Database model
        $server.Query("CREATE DATABASE $simpleRecovery")
        Stop-DbaProcess -SqlInstance $TestConfig.instance2 -Database model
        $server.Query("CREATE DATABASE $psudoSimpleRecovery")

        Set-DbaDbRecoveryModel -sqlInstance $TestConfig.instance2 -RecoveryModel BulkLogged -Database $bulkLoggedRecovery -Confirm:$false
        Set-DbaDbRecoveryModel -SqlInstance $TestConfig.instance2 -RecoveryModel Simple -Database $simpleRecovery -Confirm:$false
        Set-DbaDbRecoveryModel -SqlInstance $TestConfig.instance2 -RecoveryModel Simple -Database $psudoSimpleRecovery -Confirm:$false
        Set-DbaDbRecoveryModel -SqlInstance $TestConfig.instance2 -RecoveryModel Full -Database $psudoSimpleRecovery -Confirm:$false

    }
    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2 -Database $fullRecovery, $bulkLoggedRecovery, $simpleRecovery, $psudoSimpleRecovery
    }

    Context "Default Execution" {
        It "Should return $fullRecovery, $psudoSimpleRecovery, and Model" {
            $results = Test-DbaDbRecoveryModel -SqlInstance $TestConfig.instance2 -Database $fullRecovery, $psudoSimpleRecovery, 'Model'
            $results.Database | Should -BeIn ($fullRecovery, $psudoSimpleRecovery, 'Model')
        }
    }

    Context "Full Recovery" {
        It "Should return $fullRecovery and $psudoSimpleRecovery" {
            $results = Test-DbaDbRecoveryModel -SqlInstance $TestConfig.instance2 -RecoveryModel Full -Database $fullRecovery, $psudoSimpleRecovery -ExcludeDatabase 'Model'
            $results.Database | Should -BeIn ($fullRecovery, $psudoSimpleRecovery)
        }
    }

    Context "Bulk Logged Recovery" {
        It "Should return $bulkLoggedRecovery" {
            $results = Test-DbaDbRecoveryModel -SqlInstance $TestConfig.instance2 -RecoveryModel Bulk_Logged -Database $bulkLoggedRecovery
            $results.Database | Should -Be "$bulkLoggedRecovery"
        }
    }

    Context "Simple Recovery" {
        It "Should return $simpleRecovery" {
            $results = Test-DbaDbRecoveryModel -SqlInstance $TestConfig.instance2 -RecoveryModel Simple -Database $simpleRecovery
            $results.Database | Should -Be "$simpleRecovery"
        }
    }

    Context "Psudo Simple Recovery" {
        It "Should return $psudoSimpleRecovery" {
            $results = Test-DbaDbRecoveryModel -SqlInstance $TestConfig.instance2 -RecoveryModel Full | Where-Object { $_.database -eq "$psudoSimpleRecovery" }
            $results.Database | Should -Be "$psudoSimpleRecovery"
        }
    }

    Context "Error Check" {
        It "Should Throw Error for Incorrect Recovery Model" {
            { Test-DbaDbRecoveryModel -SqlInstance $TestConfig.instance2 -RecoveryModel Awesome -EnableException -Database 'dontexist' } | Should -Throw
        }

        It "Should Throw Error for a DB Connection Error" {
            Mock Connect-DbaInstance { Throw } -ModuleName dbatools
            { Test-DbaDbRecoveryModel -SqlInstance $TestConfig.instance2 -EnableException } | Should -Throw
        }

        It "Should Throw Error for Output Error" {
            Mock Select-DefaultView { Throw } -ModuleName dbatools
            { Test-DbaDbRecoveryModel -SqlInstance $TestConfig.instance2 -EnableException } | Should -Throw
        }
    }


}