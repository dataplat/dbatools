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
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        Stop-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Database model
        $server.Query("CREATE DATABASE $fullRecovery")
        Stop-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Database model
        $server.Query("CREATE DATABASE $bulkLoggedRecovery")
        Stop-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Database model
        $server.Query("CREATE DATABASE $simpleRecovery")
        Stop-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Database model
        $server.Query("CREATE DATABASE $psudoSimpleRecovery")

        Set-DbaDbRecoveryModel -sqlInstance $TestConfig.InstanceSingle -RecoveryModel BulkLogged -Database $bulkLoggedRecovery
        Set-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -RecoveryModel Simple -Database $simpleRecovery
        Set-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -RecoveryModel Simple -Database $psudoSimpleRecovery
        Set-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -RecoveryModel Full -Database $psudoSimpleRecovery

    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $fullRecovery, $bulkLoggedRecovery, $simpleRecovery, $psudoSimpleRecovery
    }

    Context "Default Execution" {
        It "Should return $fullRecovery, $psudoSimpleRecovery, and Model" {
            $results = Test-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -Database $fullRecovery, $psudoSimpleRecovery, 'Model' -OutVariable "global:dbatoolsciOutput"
            $results.Database | Should -BeIn ($fullRecovery, $psudoSimpleRecovery, 'Model')
        }
    }

    Context "Full Recovery" {
        It "Should return $fullRecovery and $psudoSimpleRecovery" {
            $results = Test-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -RecoveryModel Full -Database $fullRecovery, $psudoSimpleRecovery -ExcludeDatabase 'Model'
            $results.Database | Should -BeIn ($fullRecovery, $psudoSimpleRecovery)
        }
    }

    Context "Bulk Logged Recovery" {
        It "Should return $bulkLoggedRecovery" {
            $results = Test-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -RecoveryModel Bulk_Logged -Database $bulkLoggedRecovery
            $results.Database | Should -Be "$bulkLoggedRecovery"
        }
    }

    Context "Simple Recovery" {
        It "Should return $simpleRecovery" {
            $results = Test-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -RecoveryModel Simple -Database $simpleRecovery
            $results.Database | Should -Be "$simpleRecovery"
        }
    }

    Context "Psudo Simple Recovery" {
        It "Should return $psudoSimpleRecovery" {
            $results = Test-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -RecoveryModel Full | Where-Object { $_.database -eq "$psudoSimpleRecovery" }
            $results.Database | Should -Be "$psudoSimpleRecovery"
        }
    }

    Context "Error Check" {
        It "Should Throw Error for Incorrect Recovery Model" {
            { Test-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -RecoveryModel Awesome -EnableException -Database 'dontexist' } | Should -Throw
        }

        It "Should Throw Error for a DB Connection Error" {
            Mock Connect-DbaInstance { Throw } -ModuleName dbatools
            { Test-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -EnableException } | Should -Throw
        }

        It "Should Throw Error for Output Error" {
            Mock Select-DefaultView { Throw } -ModuleName dbatools
            { Test-DbaDbRecoveryModel -SqlInstance $TestConfig.InstanceSingle -EnableException } | Should -Throw
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ConfiguredRecoveryModel",
                "ActualRecoveryModel"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ConfiguredRecoveryModel",
                "ActualRecoveryModel"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $outputTypes = @($help.returnValues.returnValue.type.name)
            ($outputTypes -match "PSCustomObject").Count | Should -BeGreaterThan 0
        }
    }

}