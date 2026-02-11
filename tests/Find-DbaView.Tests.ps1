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

    Context "Output validation" {
        BeforeAll {
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name "dbatoolsci_viewoutput"
            $outputView = @"
CREATE VIEW dbo.v_dbatoolsci_outputtest
AS
    SELECT [sid],[loginname],[sysadmin]
    FROM [master].[sys].[syslogins];
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_viewoutput" -Query $outputView
            $result = Find-DbaView -SqlInstance $TestConfig.InstanceSingle -Pattern dbatoolsci_outputtest -Database "dbatoolsci_viewoutput"
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_viewoutput" -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "SqlInstance",
                "Database",
                "DatabaseId",
                "Schema",
                "Name",
                "Owner",
                "IsSystemObject",
                "CreateDate",
                "LastModified",
                "ViewTextFound"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Does not include excluded properties in the default display" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "View" -Because "View should be excluded from default display"
            $defaultProps | Should -Not -Contain "ViewFullText" -Because "ViewFullText should be excluded from default display"
        }

        It "Has the additional properties available" {
            $result[0].psobject.Properties["View"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["ViewFullText"] | Should -Not -BeNullOrEmpty
        }
    }
}