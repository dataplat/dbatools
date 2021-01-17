$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'FilePath', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }

    Context "PII Known Names" {

        $piiKnownNames = Get-Content "$PSScriptRoot\..\src\bin\datamasking\pii-knownnames.json" -Raw | ConvertFrom-Json
        $randomizerTypes = Get-Content "$PSScriptRoot\..\src\bin\randomizer\en.randomizertypes.csv" | ConvertFrom-Csv -Delimiter ','

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

        $piiPatterns = Get-Content "$PSScriptRoot\..\src\bin\datamasking\pii-patterns.json" -Raw | ConvertFrom-Json
        $randomizerTypes = Get-Content "$PSScriptRoot\..\src\bin\randomizer\en.randomizertypes.csv" | ConvertFrom-Csv -Delimiter ','

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

        Invoke-DbaQuery -SqlInstance $script:instance1 -Database master -Query $query

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

        Invoke-DbaQuery -SqlInstance $script:instance1 -Database $dbname -Query $query

        $file = New-DbaDbMaskingConfig -SqlInstance $script:instance1 -Database $dbname -Table Customer -Path "C:\temp\datamasking"

    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
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