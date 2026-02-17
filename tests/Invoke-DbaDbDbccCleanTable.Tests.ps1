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

    Context "Validate standard output" {
        BeforeAll {
            $props = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Object",
                "Cmd",
                "Output"
            )
            $result = Invoke-DbaDbDbccCleanTable -SqlInstance $TestConfig.InstanceSingle -Database "tempdb" -Object "dbo.dbatoolct_example" -OutVariable "global:dbatoolsciOutput"
        }

        It "Should return ComputerName property" {
            $result[0].PSObject.Properties["ComputerName"].Name | Should -Be "ComputerName"
        }

        It "Should return InstanceName property" {
            $result[0].PSObject.Properties["InstanceName"].Name | Should -Be "InstanceName"
        }

        It "Should return SqlInstance property" {
            $result[0].PSObject.Properties["SqlInstance"].Name | Should -Be "SqlInstance"
        }

        It "Should return Database property" {
            $result[0].PSObject.Properties["Database"].Name | Should -Be "Database"
        }

        It "Should return Object property" {
            $result[0].PSObject.Properties["Object"].Name | Should -Be "Object"
        }

        It "Should return Cmd property" {
            $result[0].PSObject.Properties["Cmd"].Name | Should -Be "Cmd"
        }

        It "Should return Output property" {
            $result[0].PSObject.Properties["Output"].Name | Should -Be "Output"
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

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Object",
                "Cmd",
                "Output"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}