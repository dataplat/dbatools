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

    Context "Output Validation" {
        BeforeAll {
            $result = New-DbaDacProfile -SqlInstance $TestConfig.InstanceSingle -Database $dbname -EnableException
        }

        AfterAll {
            if ($result.FileName) {
                Remove-Item -Path $result.FileName -ErrorAction SilentlyContinue
            }
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "SqlInstance",
                "Database",
                "FileName",
                "ConnectionString"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the expected hidden properties accessible via Select-Object" {
            $hiddenProps = @(
                "ComputerName",
                "InstanceName",
                "ProfileTemplate"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $hiddenProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should exist but be hidden from default view"
            }
        }

        It "Has all seven documented properties" {
            $allProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "FileName",
                "ConnectionString",
                "ProfileTemplate"
            )
            $actualProps = $result.PSObject.Properties.Name
            $actualProps.Count | Should -Be $allProps.Count
            foreach ($prop in $allProps) {
                $actualProps | Should -Contain $prop
            }
        }
    }
}