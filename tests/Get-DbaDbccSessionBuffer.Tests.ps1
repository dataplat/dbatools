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

    Context "Output Validation - InputBuffer" {
        BeforeAll {
            $result = Get-DbaDbccSessionBuffer -SqlInstance $TestConfig.InstanceSingle -Operation InputBuffer -All -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'SessionId',
                'EventType',
                'Parameters',
                'EventInfo'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Output Validation - OutputBuffer" {
        BeforeAll {
            $result = Get-DbaDbccSessionBuffer -SqlInstance $TestConfig.InstanceSingle -Operation OutputBuffer -All -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'SessionId',
                'Buffer'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has HexBuffer property available via Select-Object" {
            $result[0].PSObject.Properties.Name | Should -Contain 'HexBuffer' -Because "property 'HexBuffer' should be available but not in default display"
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
}