#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDacProfile",
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
                "Path",
                "ConnectionString",
                "PublishOptions",
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

        # Set variables. They are available in all the It blocks.
        $dbname = "dbatoolsci_publishprofile"
        $db = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbname
        $null = $db.Query("CREATE TABLE dbo.example (id int);
            INSERT dbo.example
            SELECT top 100 1
            FROM sys.objects")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "returns the right results" {
        $publishprofile = New-DbaDacProfile -SqlInstance $TestConfig.InstanceSingle -Database $dbname
        $publishprofile.FileName -match "publish.xml" | Should -Be $true
        Remove-Item -Path $publishprofile.FileName -ErrorAction SilentlyContinue
    }

    Context "Output validation" {
        BeforeAll {
            $result = New-DbaDacProfile -SqlInstance $TestConfig.InstanceSingle -Database $dbname
        }

        AfterAll {
            if ($result) {
                Remove-Item -Path $result.FileName -ErrorAction SilentlyContinue
            }
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            $result | Should -Not -BeNullOrEmpty
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("SqlInstance", "Database", "FileName", "ConnectionString")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Excludes the expected properties from default display" {
            $result | Should -Not -BeNullOrEmpty
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "ComputerName" -Because "ComputerName should be excluded from default display"
            $defaultProps | Should -Not -Contain "InstanceName" -Because "InstanceName should be excluded from default display"
            $defaultProps | Should -Not -Contain "ProfileTemplate" -Because "ProfileTemplate should be excluded from default display"
        }
    }
}