#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaTrace",
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
                "Id",
                "Default",
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

        $traceconfig = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName DefaultTraceEnabled

        if ($traceconfig.RunningValue -eq $false) {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $server.Query("EXEC sp_configure 'show advanced options', 1;")
            $server.Query("RECONFIGURE WITH OVERRIDE")
            $server.Query("EXEC sp_configure 'default trace enabled', 1;")
            $server.Query("RECONFIGURE WITH OVERRIDE")
            $server.Query("EXEC sp_configure 'show advanced options', 0;")
            $server.Query("RECONFIGURE WITH OVERRIDE")
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($traceconfig.RunningValue -eq $false) {
            $server.Query("EXEC sp_configure 'show advanced options', 1;")
            $server.Query("RECONFIGURE WITH OVERRIDE")
            $server.Query("EXEC sp_configure 'default trace enabled', 0;")
            $server.Query("RECONFIGURE WITH OVERRIDE")
            $server.Query("EXEC sp_configure 'show advanced options', 0;")
            $server.Query("RECONFIGURE WITH OVERRIDE")
            #$null = Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -ConfigName DefaultTraceEnabled -Value $false
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Test Check Default Trace" {
        It "Should find at least one trace file" {
            $results = Get-DbaTrace -SqlInstance $TestConfig.InstanceSingle
            $results.Id.Count -gt 0 | Should -Be $true
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaTrace -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns results" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Returns output of PSCustomObject type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Id",
                "Status",
                "IsRunning",
                "Path",
                "MaxSize",
                "StopTime",
                "MaxFiles",
                "IsRowset",
                "IsRollover",
                "IsShutdown",
                "IsDefault",
                "BufferCount",
                "BufferSize",
                "FilePosition",
                "ReaderSpid",
                "StartTime",
                "LastEventTime",
                "EventCount",
                "DroppedEventCount"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Excludes Parent, RemotePath, and SqlCredential from default display" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "Parent" -Because "Parent is excluded via Select-DefaultView -ExcludeProperty"
            $defaultProps | Should -Not -Contain "RemotePath" -Because "RemotePath is excluded via Select-DefaultView -ExcludeProperty"
            $defaultProps | Should -Not -Contain "SqlCredential" -Because "SqlCredential is excluded via Select-DefaultView -ExcludeProperty"
        }

        It "Has Parent and RemotePath available as non-default properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $allProps = $result[0].PSObject.Properties.Name
            $allProps | Should -Contain "Parent" -Because "Parent should be accessible via Select-Object *"
            $allProps | Should -Contain "RemotePath" -Because "RemotePath should be accessible via Select-Object *"
        }
    }
}