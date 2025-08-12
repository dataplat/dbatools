#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName               = "dbatools",
    $CommandName              = [System.IO.Path]::GetFileName($PSCommandPath.Replace('.Tests.ps1', '')),
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'FilePath', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }

    Context "PII Known Names" {

        $piiKnownNames = Get-Content "$PSScriptRoot\..\bin\datamasking\pii-knownnames.json" -Raw | ConvertFrom-Json
        $randomizerTypes = Get-Content "$PSScriptRoot\..\bin\randomizer\en.randomizertypes.csv" | ConvertFrom-Csv -Delimiter ','

        It "All masking types match randomizer types" {
            # Arrange
            $maskingTypesOK = $true

            # Act
            $piiKnownNames | ForEach-Object {
                $maskingTypesOK = $maskingTypesOK -and ($_.MaskingType -in $randomizerTypes.Type)
            }

            # Assert
            $maskingTypesOK | Should -Be $true
        }

        It "All masking subtypes match randomizer subtypes" {
            # Arrange
            $maskingSubtypesOK = $true

            # Act
            $piiKnownNames | ForEach-Object {
                $maskingSubtypesOK = $maskingSubtypesOK -and ($_.MaskingSubType -in $randomizerTypes.SubType)
            }

            # Assert
            $maskingSubtypesOK | Should -Be $true
        }

    }

    Context "PII patterns" {

        $piiPatterns = Get-Content "$PSScriptRoot\..\bin\datamasking\pii-patterns.json" -Raw | ConvertFrom-Json
        $randomizerTypes = Get-Content "$PSScriptRoot\..\bin\randomizer\en.randomizertypes.csv" | ConvertFrom-Csv -Delimiter ','

        It "All masking types match randomizer types" {
            # Arrange
            $maskingTypesOK = $true

            # Act
            $piiPatterns | ForEach-Object {
                $maskingTypesOK = $maskingTypesOK -and ($_.MaskingType -in $randomizerTypes.Type)
            }

            # Assert
            $maskingTypesOK | Should -Be $true
        }

        It "All masking subtypes match randomizer subtypes" {
            # Arrange
            $maskingSubtypesOK = $true

            # Act
            $piiPatterns | ForEach-Object {
                $maskingSubtypesOK = $maskingSubtypesOK -and ($_.MaskingSubType -in $randomizerTypes.SubType)
            }

            # Assert
            $maskingSubtypesOK | Should -Be $true
        }

    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatools_maskingtest"
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

        $file = New-DbaDbMaskingConfig -SqlInstance $TestConfig.instance1 -Database $dbname -Table Customer -Path "$($TestConfig.Temp)\datamasking"

    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname -Confirm:$false
        Remove-Item -Path "$($TestConfig.Temp)\datamasking" -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "gives no errors with a correct json file" {
        $findings = @()
        $findings += Test-DbaDbDataMaskingConfig -FilePath $file.FullName

        $findings.Count | Should -Be 0
    }

    It "gives errors with an incorrect json file" {
        # Retrieve the JSON content
        $json = Get-Content -Path $file.FullName | ConvertFrom-Json

        # Break the content by removing a property
        $json.Tables[0].Columns[7].PSObject.Properties.Remove("SubType")

        # Write the JSON back to the file
        $json | ConvertTo-Json -Depth 5 | Out-File $file.FullName -Force

        $findings = @()
        $findings += Test-DbaDbDataMaskingConfig -FilePath $file.FullName

        $findings.Count | Should -Be 1
    }

}
