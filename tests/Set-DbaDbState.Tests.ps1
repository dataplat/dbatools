#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbState",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "AllDatabases",
                "ReadOnly",
                "ReadWrite",
                "Online",
                "Offline",
                "Emergency",
                "Detached",
                "SingleUser",
                "RestrictedUser",
                "MultiUser",
                "Force",
                "EnableException",
                "InputObject"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Parameters validation" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $serverConnection = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $paramValidationDb = "dbatoolsci_dbsetstate_online"
            $serverConnection.Query("CREATE DATABASE $paramValidationDb")

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $paramValidationDb

            # As this is the last block we do not need to reset the $PSDefaultParameterValues.
        }
        It "Stops if no Database or AllDatabases" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -EnableException } | Should -Throw "You must specify"
        }

        It "Is nice by default" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 *> $null } | Should -Not -Throw "You must specify"
        }

        It "Errors out when multiple 'access' params are passed with EnableException" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $paramValidationDb -SingleUser -RestrictedUser -EnableException } | Should -Throw "You can only specify one of: -SingleUser,-RestrictedUser,-MultiUser"
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $paramValidationDb -MultiUser -RestrictedUser -EnableException } | Should -Throw "You can only specify one of: -SingleUser,-RestrictedUser,-MultiUser"
        }

        It "Errors out when multiple 'access' params are passed without EnableException" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $paramValidationDb -SingleUser -RestrictedUser *> $null } | Should -Not -Throw
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $paramValidationDb -MultiUser -RestrictedUser *> $null } | Should -Not -Throw
            $accessParamsResult = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $paramValidationDb -SingleUser -RestrictedUser *> $null
            $accessParamsResult | Should -BeNullOrEmpty
        }

        It "Errors out when multiple 'status' params are passed with EnableException" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $paramValidationDb -Offline -Online -EnableException } | Should -Throw "You can only specify one of: -Online,-Offline,-Emergency,-Detached"
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $paramValidationDb -Emergency -Online -EnableException } | Should -Throw "You can only specify one of: -Online,-Offline,-Emergency,-Detached"
        }

        It "Errors out when multiple 'status' params are passed without Silent" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $paramValidationDb -Offline -Online *> $null } | Should -Not -Throw
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $paramValidationDb -Emergency -Online *> $null } | Should -Not -Throw
            $statusParamsResult = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $paramValidationDb -Offline -Online *> $null
            $statusParamsResult | Should -BeNullOrEmpty
        }

        It "Errors out when multiple 'rw' params are passed with EnableException" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $paramValidationDb -ReadOnly -ReadWrite -EnableException } | Should -Throw "You can only specify one of: -ReadOnly,-ReadWrite"
        }

        It "Errors out when multiple 'rw' params are passed without EnableException" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $paramValidationDb -ReadOnly -ReadWrite *> $null } | Should -Not -Throw
            $rwParamsResult = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $paramValidationDb -ReadOnly -ReadWrite *> $null
            $rwParamsResult | Should -BeNullOrEmpty
        }
    }
    Context "Operations on databases" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $operationsServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $onlineDb = "dbatoolsci_dbsetstate_online"
            $offlineDb = "dbatoolsci_dbsetstate_offline"
            $emergencyDb = "dbatoolsci_dbsetstate_emergency"
            $singleUserDb = "dbatoolsci_dbsetstate_single"
            $restrictedUserDb = "dbatoolsci_dbsetstate_restricted"
            $multiUserDb = "dbatoolsci_dbsetstate_multi"
            $readWriteDb = "dbatoolsci_dbsetstate_rw"
            $readOnlyDb = "dbatoolsci_dbsetstate_ro"

            $allTestDatabases = @($onlineDb, $offlineDb, $emergencyDb, $singleUserDb, $restrictedUserDb, $multiUserDb, $readWriteDb, $readOnlyDb)

            # Clean up any existing test databases
            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $allTestDatabases | Remove-DbaDatabase

            # Create test databases
            foreach ($dbName in $allTestDatabases) {
                $operationsServer.Query("CREATE DATABASE $dbName")
            }

            # Verify setup
            $verifyDatabases = $operationsServer.Query("select name from sys.databases")
            $createdDatabases = $verifyDatabases | Where-Object name -in $allTestDatabases
            $setupSuccessful = $createdDatabases.Count -eq 8

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Reset databases to normal state before cleanup
            $splatResetState = @{
                SqlInstance = $TestConfig.instance2
                Database    = @($onlineDb, $offlineDb, $emergencyDb, $singleUserDb, $restrictedUserDb, $readWriteDb)
                Online      = $true
                ReadWrite   = $true
                MultiUser   = $true
                Force       = $true
            }
            $null = Set-DbaDbState @splatResetState

            # Remove all test databases
            Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $allTestDatabases

            # As this is the last block we do not need to reset the $PSDefaultParameterValues.
        }
        # just to have a correct report on how much time BeforeAll takes
        It "Waits for BeforeAll to finish" {
            $setupSuccessful | Should -BeTrue
        }
        It "Honors the Database parameter" {
            $emergencyResult = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $offlineDb -Emergency -Force
            $emergencyResult.DatabaseName | Should -Be $offlineDb
            $emergencyResult.Status | Should -Be "EMERGENCY"
            $multiDbResults = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $onlineDb, $offlineDb -Emergency -Force
            $multiDbResults.Status.Count | Should -Be 2
        }

        It "Honors the ExcludeDatabase parameter" {
            $allDatabasesQuery = $operationsServer.Query("select name from sys.databases")
            $nonTestDatabases = ($allDatabasesQuery | Where-Object Name -notin $allTestDatabases).name
            $excludeDbResults = Set-DbaDbState -SqlInstance $TestConfig.instance2 -ExcludeDatabase $nonTestDatabases -Online -Force
            $excludeComparison = Compare-Object -ReferenceObject ($excludeDbResults.DatabaseName) -DifferenceObject $allTestDatabases
            $excludeComparison.Status.Count | Should -Be 0
        }

        It "Sets a database as online" {
            $null = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $onlineDb -Emergency -Force
            $onlineResult = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $onlineDb -Online -Force
            $onlineResult.DatabaseName | Should -Be $onlineDb
            $onlineResult.Status | Should -Be "ONLINE"
        }

        It "Sets a database as offline" {
            $offlineResult = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $offlineDb -Offline -Force
            $offlineResult.DatabaseName | Should -Be $offlineDb
            $offlineResult.Status | Should -Be "OFFLINE"
        }

        It "Sets a database as emergency" {
            $emergencyStateResult = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $emergencyDb -Emergency -Force
            $emergencyStateResult.DatabaseName | Should -Be $emergencyDb
            $emergencyStateResult.Status | Should -Be "EMERGENCY"
        }

        It "Sets a database as single_user" {
            $singleUserResult = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $singleUserDb -SingleUser -Force
            $singleUserResult.DatabaseName | Should -Be $singleUserDb
            $singleUserResult.Access | Should -Be "SINGLE_USER"
        }

        It "Sets a database as multi_user" {
            $null = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $multiUserDb -RestrictedUser -Force
            $multiUserResult = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $multiUserDb -MultiUser -Force
            $multiUserResult.DatabaseName | Should -Be $multiUserDb
            $multiUserResult.Access | Should -Be "MULTI_USER"
        }

        It "Sets a database as restricted_user" {
            $restrictedUserResult = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $restrictedUserDb -RestrictedUser -Force
            $restrictedUserResult.DatabaseName | Should -Be $restrictedUserDb
            $restrictedUserResult.Access | Should -Be "RESTRICTED_USER"
        }

        It "Sets a database as read_write" {
            $null = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $readWriteDb -ReadOnly -Force
            $readWriteResult = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $readWriteDb -ReadWrite -Force
            $readWriteResult.DatabaseName | Should -Be $readWriteDb
            $readWriteResult.RW | Should -Be "READ_WRITE"
        }

        It "Sets a database as read_only" {
            $readOnlyResult = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $readOnlyDb -ReadOnly -Force
            $readOnlyResult.DatabaseName | Should -Be $readOnlyDb
            $readOnlyResult.RW | Should -Be "READ_ONLY"
        }

        It "Works when piped from Get-DbaDbState" {
            $pipeDbStateResults = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $readWriteDb, $readOnlyDb | Set-DbaDbState -Online -MultiUser -Force
            $pipeDbStateResults.Status.Count | Should -Be 2
            $pipeDbStateComparison = Compare-Object -ReferenceObject ($pipeDbStateResults.DatabaseName) -DifferenceObject @($readWriteDb, $readOnlyDb)
            $pipeDbStateComparison.Status.Count | Should -Be 0
        }

        It "Works when piped from Get-DbaDatabase" {
            $pipeDatabaseResults = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $readWriteDb, $readOnlyDb | Set-DbaDbState -Online -MultiUser -Force
            $pipeDatabaseResults.Status.Count | Should -Be 2
            $pipeDatabaseComparison = Compare-Object -ReferenceObject ($pipeDatabaseResults.DatabaseName) -DifferenceObject @($readWriteDb, $readOnlyDb)
            $pipeDatabaseComparison.Status.Count | Should -Be 0
        }

        It "Has the correct properties" {
            $propertiesTestResult = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $onlineDb -Emergency -Force
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "RW",
                "Status",
                "Access",
                "Notes",
                "Database"
            )
            ($propertiesTestResult.PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProperties | Sort-Object)
        }

        It "Has the correct default properties" {
            $defaultPropsTestResult = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $onlineDb -Emergency -Force
            $expectedDefaultProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "RW",
                "Status",
                "Access",
                "Notes"
            )
            ($defaultPropsTestResult.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedDefaultProperties | Sort-Object)
        }
    }
}
