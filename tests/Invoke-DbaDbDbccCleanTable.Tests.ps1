#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbDbccCleanTable",
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
                "Object",
                "BatchSize",
                "NoInformationalMessages",
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
        $null = $db.Query("CREATE TABLE dbo.dbatoolct_example (object_id int, [definition] nvarchar(max),Document varchar(2000));
        INSERT INTO dbo.dbatoolct_example([object_id], [definition], Document) Select [object_id], [definition], REPLICATE('ab', 800) from master.sys.sql_modules;
        ALTER TABLE dbo.dbatoolct_example DROP COLUMN Definition, Document;")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        try {
            $null = $db.Query("DROP TABLE dbo.dbatoolct_example")
        } catch {
            $null = 1
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Invoke-DbaDbDbccCleanTable -SqlInstance $TestConfig.InstanceSingle -Database "tempdb" -Object "dbo.dbatoolct_example" -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Object",
                "Cmd",
                "Output"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "returns correct results" {
            $result.Database -eq "tempdb" | Should -Be $true
            $result.Object -eq "dbo.dbatoolct_example" | Should -Be $true
            $result.Output.Substring(0, 25) -eq "DBCC execution completed." | Should -Be $true
        }
    }

    Context "Validate BatchSize parameter" {
        BeforeAll {
            $result = Invoke-DbaDbDbccCleanTable -SqlInstance $TestConfig.InstanceSingle -Database "tempdb" -Object "dbo.dbatoolct_example" -BatchSize 1000
        }

        It "returns results for table" {
            $result.Cmd -eq "DBCC CLEANTABLE('tempdb', 'dbo.dbatoolct_example', 1000)" | Should -Be $true
            $result.Output.Substring(0, 25) -eq "DBCC execution completed." | Should -Be $true
        }
    }

    Context "Validate NoInformationalMessages parameter" {
        BeforeAll {
            $result = Invoke-DbaDbDbccCleanTable -SqlInstance $TestConfig.InstanceSingle -Database "tempdb" -Object "dbo.dbatoolct_example" -NoInformationalMessages
        }

        It "returns results for table" {
            $result.Cmd -eq "DBCC CLEANTABLE('tempdb', 'dbo.dbatoolct_example') WITH NO_INFOMSGS" | Should -Be $true
            $result.Output -eq $null | Should -Be $true
        }
    }
}