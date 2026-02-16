#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaPfDataCollectorCounter",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "CollectorSet",
                "Collector",
                "Counter",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaPfDataCollectorSetTemplate -Template "Long Running Queries" |
            Import-DbaPfDataCollectorSetTemplate -ComputerName $TestConfig.InstanceSingle |
            Get-DbaPfDataCollector |
            Get-DbaPfDataCollectorCounter -Counter "\LogicalDisk(*)\Avg. Disk Queue Length" |
            Remove-DbaPfDataCollectorCounter

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaPfDataCollectorSet -ComputerName $TestConfig.InstanceSingle -CollectorSet "Long Running Queries" |
            Remove-DbaPfDataCollectorSet

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When adding a counter to a data collector" {
        BeforeAll {
            $results = Get-DbaPfDataCollectorSet -ComputerName $TestConfig.InstanceSingle -CollectorSet "Long Running Queries" |
                Get-DbaPfDataCollector |
                Add-DbaPfDataCollectorCounter -Counter "\LogicalDisk(*)\Avg. Disk Queue Length" -OutVariable "global:dbatoolsciOutput"
        }

        It "Returns the correct DataCollectorSet" {
            $results.DataCollectorSet | Should -Be "Long Running Queries"
        }

        It "Returns the correct counter name" {
            $results.Name | Should -Be "\LogicalDisk(*)\Avg. Disk Queue Length"
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
                "DataCollectorSet",
                "DataCollector",
                "DataCollectorSetXml",
                "Name",
                "FileName",
                "CounterObject",
                "Credential"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "DataCollectorSet",
                "DataCollector",
                "Name",
                "FileName"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}