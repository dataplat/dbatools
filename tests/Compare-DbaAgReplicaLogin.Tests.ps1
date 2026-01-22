#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAgReplicaLogin",
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
                "AvailabilityGroup",
                "ExcludeSystemLogin",
                "IncludeModifiedDate",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            $result = [PSCustomObject]@{
                AvailabilityGroup = "AG1"
                Replica           = "sql2016"
                LoginName         = "testlogin"
                Status            = "Present"
                ModifyDate        = Get-Date
                CreateDate        = Get-Date
            }
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "AvailabilityGroup",
                "Replica",
                "LoginName",
                "Status",
                "ModifyDate",
                "CreateDate"
            )
            $result = [PSCustomObject]@{
                AvailabilityGroup = "AG1"
                Replica           = "sql2016"
                LoginName         = "testlogin"
                Status            = "Present"
                ModifyDate        = Get-Date
                CreateDate        = Get-Date
            }
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }
    }
}
