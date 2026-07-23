#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbTrigger",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/New-DbaDbTrigger.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Name",
                "Definition",
                "DdlEvent",
                "IsEnabled",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # Each leg gets its own database so the tests do not couple through shared state.
        $dbBasic = "dbatoolsci_newtrigger_$random"
        $dbPipe1 = "dbatoolsci_newtrigger_p1_$random"
        $dbPipe2 = "dbatoolsci_newtrigger_p2_$random"
        $allDatabases = @($dbBasic, $dbPipe1, $dbPipe2)
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $allDatabases

        # A database-scoped DDL trigger body - the statements that follow AS. SMO synthesises the header
        # (CREATE TRIGGER ... ON DATABASE FOR CREATE_TABLE) from the name and the event set.
        $triggerBody = "PRINT 'dbatoolsci ddl trigger fired'"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $allDatabases -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Gates the create and changes nothing" {
            # The ShouldProcess text is emitted from the module-scoped hop body and is host-direct, so the
            # distinguishing assertion is that the side effect did NOT happen - no trigger was created.
            $splatWhatIf = @{
                SqlInstance = $InstanceSingle
                Database    = $dbBasic
                Name        = "trWhatIf"
                Definition  = $triggerBody
                DdlEvent    = "CreateTable"
                WhatIf      = $true
            }
            New-DbaDbTrigger @splatWhatIf

            $created = Get-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbBasic | Where-Object Name -eq "trWhatIf"
            $created | Should -BeNullOrEmpty
        }
    }

    Context "Command behavior" {
        It "Creates a DDL trigger via -SqlInstance and re-emits the decorated object" {
            $splatBasic = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                Name            = "trBasic"
                Definition      = $triggerBody
                DdlEvent        = "CreateTable"
                EnableException = $true
                Confirm         = $false
            }
            $result = New-DbaDbTrigger @splatBasic
            $result.Name | Should -Be "trBasic"
            # Decoration parity with Get-DbaDbTrigger so Get -> New -> Get composes (default view carries no Database column).
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            # Read back independently.
            (Get-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbBasic | Where-Object Name -eq "trBasic").Name | Should -Be "trBasic"
        }

        It "Creates a disabled trigger with -IsEnabled:`$false" {
            $splatDisabled = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                Name            = "trDisabled"
                Definition      = $triggerBody
                DdlEvent        = "CreateTable"
                IsEnabled       = $false
                EnableException = $true
                Confirm         = $false
            }
            $result = New-DbaDbTrigger @splatDisabled
            $result.IsEnabled | Should -Be $false
            (Get-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbBasic | Where-Object Name -eq "trDisabled").IsEnabled | Should -Be $false
        }

        It "Creates a trigger in multiple piped databases (N in, N out)" {
            # Multi-record piped leg. Two databases piped in from Get-DbaDatabase must both come back with the
            # created trigger, each resolving its own parent server.
            $results = Get-DbaDatabase -SqlInstance $InstanceSingle -Database $dbPipe1, $dbPipe2 |
                New-DbaDbTrigger -Name "trPipe" -Definition $triggerBody -DdlEvent "CreateTable" -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            $results.Name | Sort-Object -Unique | Should -Be "trPipe"
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Name            = "trNeither"
                Definition      = $triggerBody
                DdlEvent        = "CreateTable"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = New-DbaDbTrigger @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues on an unknown DDL event name" {
            $splatBadEvent = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                Name            = "trBadEvent"
                Definition      = $triggerBody
                DdlEvent        = "NotARealEvent"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnBadEvent"
            }
            $results = New-DbaDbTrigger @splatBadEvent
            $warnBadEvent | Should -BeLike "*Unknown DDL event*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues when the trigger already exists without -EnableException" {
            $null = New-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbBasic -Name "trDupe" -Definition $triggerBody -DdlEvent "CreateTable" -Confirm:$false -EnableException
            $splatDupe = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                Name            = "trDupe"
                Definition      = $triggerBody
                DdlEvent        = "CreateTable"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnDupe"
            }
            $results = New-DbaDbTrigger @splatDupe
            $warnDupe | Should -BeLike "*already exists*"
            $results | Should -BeNullOrEmpty
        }
    }
}
