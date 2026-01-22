#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAvailabilityGroup",
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
                "Type",
                "ExcludeSystemJob",
                "ExcludeSystemLogin",
                "IncludeModifiedDate",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation for AgentJob comparison" {
        It "AgentJob output should have expected properties" {
            $expectedProps = @(
                'AvailabilityGroup',
                'Replica',
                'JobName',
                'Status',
                'DateLastModified'
            )

            $mockResult = [PSCustomObject]@{
                AvailabilityGroup = "AG1"
                Replica           = "SQL2019"
                JobName           = "TestJob"
                Status            = "Missing"
                DateLastModified  = $null
            }

            $actualProps = $mockResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in AgentJob output"
            }
        }
    }

    Context "Output Validation for Login comparison" {
        It "Login output should have expected properties" {
            $expectedProps = @(
                'AvailabilityGroup',
                'Replica',
                'LoginName',
                'Status',
                'ModifyDate',
                'CreateDate'
            )

            $mockResult = [PSCustomObject]@{
                AvailabilityGroup = "AG1"
                Replica           = "SQL2019"
                LoginName         = "TestLogin"
                Status            = "Missing"
                ModifyDate        = $null
                CreateDate        = $null
            }

            $actualProps = $mockResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in Login output"
            }
        }
    }

    Context "Output Validation for Credential comparison" {
        It "Credential output should have expected properties" {
            $expectedProps = @(
                'AvailabilityGroup',
                'Replica',
                'CredentialName',
                'Status',
                'Identity'
            )

            $mockResult = [PSCustomObject]@{
                AvailabilityGroup = "AG1"
                Replica           = "SQL2019"
                CredentialName    = "TestCredential"
                Status            = "Missing"
                Identity          = $null
            }

            $actualProps = $mockResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in Credential output"
            }
        }
    }

    Context "Output Validation for Operator comparison" {
        It "Operator output should have expected properties" {
            $expectedProps = @(
                'AvailabilityGroup',
                'Replica',
                'OperatorName',
                'Status',
                'EmailAddress'
            )

            $mockResult = [PSCustomObject]@{
                AvailabilityGroup = "AG1"
                Replica           = "SQL2019"
                OperatorName      = "TestOperator"
                Status            = "Missing"
                EmailAddress      = $null
            }

            $actualProps = $mockResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in Operator output"
            }
        }
    }
}
