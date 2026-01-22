#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaView",
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
                "Database",
                "ExcludeDatabase",
                "Pattern",
                "IncludeSystemObjects",
                "IncludeSystemDatabases",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}


Describe $CommandName -Tag IntegrationTests {
    Context "Command finds Views in a System Database" {
        BeforeAll {
            $ServerView = @"
CREATE VIEW dbo.v_dbatoolsci_sysadmin
AS
    SELECT [sid],[loginname],[sysadmin]
    FROM [master].[sys].[syslogins];
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database "Master" -Query $ServerView
        }

        AfterAll {
            $DropView = "DROP VIEW dbo.v_dbatoolsci_sysadmin;"
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database "Master" -Query $DropView
        }

        BeforeEach {
            $results = Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Pattern dbatools* -IncludeSystemDatabases
        }

        It "Should find a specific View named v_dbatoolsci_sysadmin" {
            $results.Name | Should -Be "v_dbatoolsci_sysadmin"
        }

        It "Should find v_dbatoolsci_sysadmin in Master" {
            $results.Database | Should -Be "Master"
            $results.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database Master).ID
        }
    }

    Context "Command finds View in a User Database" {
        BeforeAll {
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name "dbatoolsci_viewdb"
            $DatabaseView = @"
CREATE VIEW dbo.v_dbatoolsci_sysadmin
AS
    SELECT [sid],[loginname],[sysadmin]
    FROM [master].[sys].[syslogins];
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_viewdb" -Query $DatabaseView
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_viewdb"
        }

        It "Should find a specific view named v_dbatoolsci_sysadmin" {
            $results = Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Pattern dbatools* -Database "dbatoolsci_viewdb"
            $results.Name | Should -Be "v_dbatoolsci_sysadmin"
        }

        It "Should find v_dbatoolsci_sysadmin in dbatoolsci_viewdb Database" {
            $results = Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Pattern dbatools* -Database "dbatoolsci_viewdb"
            $results.Database | Should -Be "dbatoolsci_viewdb"
            $results.DatabaseId | Should -Be (Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database dbatoolsci_viewdb).ID
        }

        It "Should find no results when Excluding dbatoolsci_viewdb" {
            $results = Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Pattern dbatools* -ExcludeDatabase "dbatoolsci_viewdb"
            $results | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name "dbatoolsci_viewdb_output"
            $DatabaseView = @"
CREATE VIEW dbo.v_output_test
AS
    SELECT [sid],[loginname],[sysadmin]
    FROM [master].[sys].[syslogins];
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_viewdb_output" -Query $DatabaseView
            $result = Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Pattern output -Database "dbatoolsci_viewdb_output" -EnableException
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_viewdb_output" -Confirm:$false
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'SqlInstance',
                'Database',
                'DatabaseId',
                'Schema',
                'Name',
                'Owner',
                'IsSystemObject',
                'CreateDate',
                'LastModified',
                'ViewTextFound'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional properties available via Select-Object *" {
            $additionalProps = @(
                'View',
                'ViewFullText'
            )
            $allProps = ($result | Select-Object -Property *).PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $allProps | Should -Contain $prop -Because "property '$prop' should be accessible"
            }
        }
    }
}