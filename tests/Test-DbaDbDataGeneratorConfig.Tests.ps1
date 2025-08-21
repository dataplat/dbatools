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

        Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database master -Query $query

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

        Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database $dbname -Query $query

        $file = New-DbaDbDataGeneratorConfig -SqlInstance $TestConfig.instance1 -Database $dbname -Table Customer -Path "$($TestConfig.Temp)\datageneration"

    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname -Confirm:$false
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

}