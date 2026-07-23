#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbTrigger",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaDbTrigger.json parameters array - exact-match surface law.
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

        $dbName = "dbatoolsci_settrigger_$random"
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $dbName

        $triggerBody = "PRINT 'dbatoolsci ddl trigger fired'"
        # Seed a trigger to alter in each leg (fresh name per leg to avoid coupling).
        $null = New-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbName -Name "trAlter" -Definition $triggerBody -DdlEvent "CreateTable"
        $null = New-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbName -Name "trEnable" -Definition $triggerBody -DdlEvent "CreateTable"
        $null = New-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbName -Name "trWhatIf" -Definition $triggerBody -DdlEvent "CreateTable"
        $null = New-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbName -Name "trPipe" -Definition $triggerBody -DdlEvent "CreateTable"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $dbName -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Gates the enable-state toggle and changes nothing" {
            # The ShouldProcess text is emitted from the module-scoped hop body and is host-direct, so the
            # distinguishing assertion is that the side effect did NOT happen - the trigger stayed enabled.
            $before = (Get-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbName | Where-Object Name -eq "trWhatIf").IsEnabled
            Set-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbName -Name "trWhatIf" -IsEnabled:$false -WhatIf
            $after = (Get-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbName | Where-Object Name -eq "trWhatIf").IsEnabled
            $before | Should -Be $true
            $after | Should -Be $true
        }
    }

    Context "Command behavior" {
        It "Alters the trigger body via -SqlInstance and re-emits the decorated object" {
            $newBody = "PRINT 'dbatoolsci altered body'"
            $splatAlter = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbName
                Name            = "trAlter"
                Definition      = $newBody
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDbTrigger @splatAlter
            $result.Name | Should -Be "trAlter"
            # Decoration parity with Get-DbaDbTrigger.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            # The altered body is reflected server-side.
            (Get-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbName | Where-Object Name -eq "trAlter").TextBody | Should -BeLike "*altered body*"
        }

        It "Toggles the enabled state independently of the body" {
            $result = Set-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbName -Name "trEnable" -IsEnabled:$false -EnableException -Confirm:$false
            $result.IsEnabled | Should -Be $false
            (Get-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbName | Where-Object Name -eq "trEnable").IsEnabled | Should -Be $false
        }

        It "Accepts piped Get-DbaDbTrigger objects (N in, N out)" {
            # Multi-record piped leg fed by the getCounterpart.
            $newBody = "PRINT 'dbatoolsci piped alter'"
            $results = Get-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbName |
                Where-Object Name -eq "trPipe" |
                Set-DbaDbTrigger -Definition $newBody -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 1
            $results.Name | Should -Be "trPipe"
            (Get-DbaDbTrigger -SqlInstance $InstanceSingle -Database $dbName | Where-Object Name -eq "trPipe").TextBody | Should -BeLike "*piped alter*"
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Name            = "trAlter"
                Definition      = "PRINT 'x'"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaDbTrigger @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Requires at least one change" {
            $splatNoChange = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbName
                Name            = "trAlter"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNoChange"
            }
            $results = Set-DbaDbTrigger @splatNoChange
            $warnNoChange | Should -BeLike "*at least one change*"
            $results | Should -BeNullOrEmpty
        }
    }
}
