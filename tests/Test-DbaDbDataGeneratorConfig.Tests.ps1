#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDbDataGeneratorConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FilePath",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $dbname = "dbatools_datagentest"
        $query = "CREATE DATABASE [$dbname]"

        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query $query

        $query = "
        CREATE TABLE [dbo].[Customer](
            [CustomerID] [int] IDENTITY(1,1) NOT NULL,
            [Firstname] [varchar](30) NULL,
            [Lastname] [varchar](50) NULL,
            [FullName] [varchar](100) NULL,
            [Address] [varchar](100) NULL,
            [Zip] [varchar](10) NULL,
            [City] [varchar](255) NULL,
            [Randomtext] [varchar](255) NULL,
            [DOB] [date] NULL
        ) ON [PRIMARY]
        "

        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Query $query

        $file = New-DbaDbDataGeneratorConfig -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Table Customer -Path "$($TestConfig.Temp)\datageneration"

    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname
        Remove-Item -Path "$($TestConfig.Temp)\datageneration" -Recurse
    }

    It "gives no errors with a correct json file" {
        $findings = @()
        $findings += Test-DbaDbDataGeneratorConfig -FilePath $file.FullName

        $findings.Count | Should -Be 0
    }

    It "gives errors with an incorrect json file" {
        # Retrieve the JSON content
        $json = Get-Content -Path $file.FullName | ConvertFrom-Json

        # Break the content by removing a property
        $json.Tables[0].Columns[8].PSObject.Properties.Remove("SubType")

        # Write the JSON back to the file
        $json | ConvertTo-Json -Depth 5 | Out-File $file.FullName -Force

        $findings = @()
        $findings += Test-DbaDbDataGeneratorConfig -FilePath $file.FullName

        $findings.Count | Should -Be 1
    }

    Context "Output validation" {
        BeforeAll {
            # Generate a fresh config file and break it to produce error output
            $outputValDbName = "dbatoolsci_datagenoutputval_$(Get-Random)"
            $outputValPath = "$($TestConfig.Temp)\dbatoolsci_datagenoutputval_$(Get-Random)"
            $null = New-Item -Path $outputValPath -ItemType Directory

            $createQuery = "CREATE DATABASE [$outputValDbName]"
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query $createQuery

            $tableQuery = "
            CREATE TABLE [dbo].[OutputTest](
                [ID] [int] IDENTITY(1,1) NOT NULL,
                [Name] [varchar](50) NULL
            ) ON [PRIMARY]
            "
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $outputValDbName -Query $tableQuery

            $outputFile = New-DbaDbDataGeneratorConfig -SqlInstance $TestConfig.InstanceSingle -Database $outputValDbName -Table OutputTest -Path $outputValPath

            # Break the config to produce error output
            $outputJson = Get-Content -Path $outputFile.FullName | ConvertFrom-Json
            $outputJson.Tables[0].Columns[1].PSObject.Properties.Remove("SubType")
            $outputJson | ConvertTo-Json -Depth 5 | Out-File $outputFile.FullName -Force

            $result = @(Test-DbaDbDataGeneratorConfig -FilePath $outputFile.FullName)
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputValDbName -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item -Path $outputValPath -Recurse -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected properties" {
            $result[0].PSObject.Properties.Name | Should -Contain "Table"
            $result[0].PSObject.Properties.Name | Should -Contain "Column"
            $result[0].PSObject.Properties.Name | Should -Contain "Value"
            $result[0].PSObject.Properties.Name | Should -Contain "Error"
        }
    }
}