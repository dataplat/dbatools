#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDbDataMaskingConfig",
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

    Context "PII Known Names" {
        BeforeAll {
            $piiKnownNames = Get-Content "$PSScriptRoot\..\bin\datamasking\pii-knownnames.json" -Raw | ConvertFrom-Json
            $randomizerTypes = Get-Content "$PSScriptRoot\..\bin\randomizer\en.randomizertypes.csv" | ConvertFrom-Csv -Delimiter ","
        }

        It "All masking types match randomizer types" {
            # Arrange
            $maskingTypesOK = $true

            # Act
            $piiKnownNames | ForEach-Object {
                $maskingTypesOK = $maskingTypesOK -and ($PSItem.MaskingType -in $randomizerTypes.Type)
            }

            # Assert
            $maskingTypesOK | Should -Be $true
        }

        It "All masking subtypes match randomizer subtypes" {
            # Arrange
            $maskingSubtypesOK = $true

            # Act
            $piiKnownNames | ForEach-Object {
                $maskingSubtypesOK = $maskingSubtypesOK -and ($PSItem.MaskingSubType -in $randomizerTypes.SubType)
            }

            # Assert
            $maskingSubtypesOK | Should -Be $true
        }
    }

    Context "PII patterns" {
        BeforeAll {
            $piiPatterns = Get-Content "$PSScriptRoot\..\bin\datamasking\pii-patterns.json" -Raw | ConvertFrom-Json
            $randomizerTypes = Get-Content "$PSScriptRoot\..\bin\randomizer\en.randomizertypes.csv" | ConvertFrom-Csv -Delimiter ","
        }

        It "All masking types match randomizer types" {
            # Arrange
            $maskingTypesOK = $true

            # Act
            $piiPatterns | ForEach-Object {
                $maskingTypesOK = $maskingTypesOK -and ($PSItem.MaskingType -in $randomizerTypes.Type)
            }

            # Assert
            $maskingTypesOK | Should -Be $true
        }

        It "All masking subtypes match randomizer subtypes" {
            # Arrange
            $maskingSubtypesOK = $true

            # Act
            $piiPatterns | ForEach-Object {
                $maskingSubtypesOK = $maskingSubtypesOK -and ($PSItem.MaskingSubType -in $randomizerTypes.SubType)
            }

            # Assert
            $maskingSubtypesOK | Should -Be $true
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the temporary files that we want to clean up after the test, we create a directory that we can delete at the end.
        $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $tempPath -ItemType Directory

        $dbName = "dbatools_maskingtest"
        $createDbQuery = "CREATE DATABASE [$dbName]"

        Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database master -Query $createDbQuery

        $createTableQuery = "
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

        Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database $dbName -Query $createTableQuery

        $file = New-DbaDbMaskingConfig -SqlInstance $TestConfig.instance1 -Database $dbName -Table Customer -Path $tempPath

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName -Confirm:$false
        Remove-Item -Path $tempPath -Recurse -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    It "gives no errors with a correct json file" {
        $findings = @(Test-DbaDbDataMaskingConfig -FilePath $file.FullName)

        $findings.Count | Should -Be 0
    }

    It "gives errors with an incorrect json file" {
        # Retrieve the JSON content
        $json = Get-Content -Path $file.FullName | ConvertFrom-Json

        # Break the content by removing a property
        $json.Tables[0].Columns[7].PSObject.Properties.Remove("SubType")

        # Write the JSON back to the file
        $json | ConvertTo-Json -Depth 5 | Out-File $file.FullName -Force

        $findings = @(Test-DbaDbDataMaskingConfig -FilePath $file.FullName)

        $findings.Count | Should -Be 1
    }

}