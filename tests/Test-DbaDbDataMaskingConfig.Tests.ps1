param($ModuleName = 'dbatools')

Describe "Test-DbaDbDataMaskingConfig" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"

        $piiKnownNames = Get-Content "$PSScriptRoot\..\bin\datamasking\pii-knownnames.json" -Raw | ConvertFrom-Json
        $piiPatterns = Get-Content "$PSScriptRoot\..\bin\datamasking\pii-patterns.json" -Raw | ConvertFrom-Json
        $randomizerTypes = Get-Content "$PSScriptRoot\..\bin\randomizer\en.randomizertypes.csv" | ConvertFrom-Csv -Delimiter ','
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDbDataMaskingConfig
        }
        It "Should have FilePath as a parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "PII Known Names" {
        It "All masking types match randomizer types" {
            $maskingTypesOK = $true
            $piiKnownNames | ForEach-Object {
                $maskingTypesOK = $maskingTypesOK -and ($_.MaskingType -in $randomizerTypes.Type)
            }
            $maskingTypesOK | Should -Be $true
        }

        It "All masking subtypes match randomizer subtypes" {
            $maskingSubtypesOK = $true
            $piiKnownNames | ForEach-Object {
                $maskingSubtypesOK = $maskingSubtypesOK -and ($_.MaskingSubType -in $randomizerTypes.SubType)
            }
            $maskingSubtypesOK | Should -Be $true
        }
    }

    Context "PII patterns" {
        It "All masking types match randomizer types" {
            $maskingTypesOK = $true
            $piiPatterns | ForEach-Object {
                $maskingTypesOK = $maskingTypesOK -and ($_.MaskingType -in $randomizerTypes.Type)
            }
            $maskingTypesOK | Should -Be $true
        }

        It "All masking subtypes match randomizer subtypes" {
            $maskingSubtypesOK = $true
            $piiPatterns | ForEach-Object {
                $maskingSubtypesOK = $maskingSubtypesOK -and ($_.MaskingSubType -in $randomizerTypes.SubType)
            }
            $maskingSubtypesOK | Should -Be $true
        }
    }
}

Describe "Test-DbaDbDataMaskingConfig Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatools_maskingtest"
        $query = "CREATE DATABASE [$dbname]"

        Invoke-DbaQuery -SqlInstance $global:instance1 -Database master -Query $query

        $query = @"
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
"@

        Invoke-DbaQuery -SqlInstance $global:instance1 -Database $dbname -Query $query

        $file = New-DbaDbMaskingConfig -SqlInstance $global:instance1 -Database $dbname -Table Customer -Path "C:\temp\datamasking"
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
    }

    It "gives no errors with a correct json file" {
        $findings = @()
        $findings += Test-DbaDbDataMaskingConfig -FilePath $file.FullName
        $findings.Count | Should -Be 0
    }

    It "gives errors with an incorrect json file" {
        $json = Get-Content -Path $file.FullName | ConvertFrom-Json
        $json.Tables[0].Columns[7].PSObject.Properties.Remove("SubType")
        $json | ConvertTo-Json -Depth 5 | Out-File $file.FullName -Force

        $findings = @()
        $findings += Test-DbaDbDataMaskingConfig -FilePath $file.FullName
        $findings.Count | Should -Be 1
    }
}
