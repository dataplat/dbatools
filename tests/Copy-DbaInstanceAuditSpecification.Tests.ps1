#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaInstanceAuditSpecification",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "AuditSpecification",
                "ExcludeAuditSpecification",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Create a mock audit specification result
            $mockResult = [PSCustomObject]@{
                DateTime          = [DbaDateTime](Get-Date)
                SourceServer      = "TestSource"
                DestinationServer = "TestDestination"
                Name              = "TestAuditSpec"
                Type              = "Server Audit Specification"
                Status            = "Successful"
                Notes             = $null
            }
            Add-Member -InputObject $mockResult -MemberType NoteProperty -Name PSStandardMembers -Value (
                [PSPropertySet]::new('DefaultDisplayPropertySet', [string[]]('DateTime', 'SourceServer', 'DestinationServer', 'Name', 'Type', 'Status', 'Notes'))
            ) -Force
            $mockResult.PSObject.TypeNames.Insert(0, 'MigrationObject')
        }

        It "Returns PSCustomObject with MigrationObject typename" {
            $mockResult.PSObject.TypeNames | Should -Contain 'MigrationObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'DateTime',
                'SourceServer',
                'DestinationServer',
                'Name',
                'Type',
                'Status',
                'Notes'
            )
            $actualProps = $mockResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "DateTime property is of type DbaDateTime" {
            $mockResult.DateTime | Should -BeOfType [DbaDateTime]
        }

        It "Type property contains 'Server Audit Specification'" {
            $mockResult.Type | Should -Be "Server Audit Specification"
        }

        It "Status property accepts valid migration states" {
            $validStatuses = @('Successful', 'Skipped', 'Failed')
            $mockResult.Status | Should -BeIn $validStatuses
        }
    }
}