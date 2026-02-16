#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbccSessionBuffer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Operation",
                "SessionId",
                "RequestId",
                "All",
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

        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
        $queryResult = $db.Query("SELECT top 10 object_id, @@Spid as MySpid FROM sys.objects")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Validate standard output for all databases" {
        BeforeAll {
            $propsInputBuffer = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SessionId",
                "EventType",
                "Parameters",
                "EventInfo"
            )
            $propsOutputBuffer = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SessionId",
                "Buffer",
                "HexBuffer"
            )
            $resultInputBuffer = Get-DbaDbccSessionBuffer -SqlInstance $TestConfig.InstanceSingle -Operation InputBuffer -All -OutVariable "global:dbatoolsciOutputInputBuffer"
            $resultOutputBuffer = Get-DbaDbccSessionBuffer -SqlInstance $TestConfig.InstanceSingle -Operation OutputBuffer -All -OutVariable "global:dbatoolsciOutputOutputBuffer"
        }

        It "Returns results for InputBuffer" {
            $resultInputBuffer.Count | Should -BeGreaterThan 0
        }

        It "Returns results for OutputBuffer" {
            $resultOutputBuffer.Count | Should -BeGreaterThan 0
        }

        It "Should return property: <_> for InputBuffer" -ForEach $propsInputBuffer {
            $resultInputBuffer[0].PSObject.Properties[$PSItem].Name | Should -Be $PSItem
        }

        It "Should return property: <_> for OutputBuffer" -ForEach $propsOutputBuffer {
            $resultOutputBuffer[0].PSObject.Properties[$PSItem].Name | Should -Be $PSItem
        }
    }

    Context "Validate returns results for SessionId" {
        BeforeAll {
            $spid = $queryResult[0].MySpid
            $resultInputBuffer = Get-DbaDbccSessionBuffer -SqlInstance $TestConfig.InstanceSingle -Operation InputBuffer -SessionId $spid
            $resultOutputBuffer = Get-DbaDbccSessionBuffer -SqlInstance $TestConfig.InstanceSingle -Operation OutputBuffer -SessionId $spid
        }

        It "Returns results for InputBuffer with correct SessionId" {
            $resultInputBuffer.SessionId | Should -Be $spid
        }

        It "Returns results for OutputBuffer with correct SessionId" {
            $resultOutputBuffer.SessionId | Should -Be $spid
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutputInputBuffer = $null
            $global:dbatoolsciOutputOutputBuffer = $null
        }

        It "Should return a PSCustomObject for InputBuffer" {
            $global:dbatoolsciOutputInputBuffer[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should return a PSCustomObject for OutputBuffer" {
            $global:dbatoolsciOutputOutputBuffer[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties for InputBuffer" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SessionId",
                "EventType",
                "Parameters",
                "EventInfo"
            )
            $actualProperties = $global:dbatoolsciOutputInputBuffer[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the expected properties for OutputBuffer" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SessionId",
                "Buffer",
                "HexBuffer"
            )
            $actualProperties = $global:dbatoolsciOutputOutputBuffer[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns for OutputBuffer" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SessionId",
                "Buffer"
            )
            $defaultColumns = $global:dbatoolsciOutputOutputBuffer[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}