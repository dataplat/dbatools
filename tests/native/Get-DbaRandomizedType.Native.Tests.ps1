#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: azure-sqldb N/A -- this command reads the module's local CSV and has no SQL endpoint; Azure SQL Database does not expose the client module filesystem. https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server
# NativeChecklist: sql-login N/A -- no SqlCredential or server parameter and no SQL connection.
# NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input.
# NativeChecklist: multi-instance-failure N/A -- no instance or computer parameter.
# NativeChecklist: whatif-confirm N/A -- the pinned command does not support ShouldProcess.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaRandomizedType",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Get-DbaRandomizedType native catalog contract" -Tag IntegrationTests {
    BeforeAll {
        $catalogModule = Get-Module $ModuleName | Where-Object ModuleType -eq Script | Select-Object -First 1
        $catalogPath = Join-Path $catalogModule.ModuleBase "bin/randomizer/en.randomizertypes.csv"
        $catalog = @(Import-Csv $catalogPath)
        $expectedAll = @($catalog | Select-Object Type, SubType, RequiredParameter -Unique | Sort-Object Type, SubType)
    }

    It "returns the sorted three-column catalog and selected object shape" {
        $actual = @(Get-DbaRandomizedType)
        $actual.Count | Should -Be $expectedAll.Count
        ($actual | ConvertTo-Json -Compress) | Should -BeExactly ($expectedAll | ConvertTo-Json -Compress)
        ($actual[0].PSObject.Properties.Name -join ",") | Should -BeExactly "Type,SubType,RequiredParameter"
        ($actual[0].PSObject.TypeNames -join ",") | Should -BeExactly ($expectedAll[0].PSObject.TypeNames -join ",")
        Get-DbaRandomizedType -RandomizedType Random -RandomizedSubType ClampString | Select-Object -ExpandProperty RequiredParameter | Should -BeExactly "Value"
        Get-DbaRandomizedType -RandomizedType Random -RandomizedSubType Replace | Select-Object -ExpandProperty RequiredParameter | Should -BeExactly "Format"
        Get-DbaRandomizedType -RandomizedType Static | Select-Object -ExpandProperty RequiredParameter | Should -BeExactly "StaticValue"
    }

    It "combines case-insensitive exact filters with regular-expression discovery" {
        $splatTypeFilters = @{
            RandomizedType    = @("name", "address")
            RandomizedSubType = @("firstname", "lastname", "zipcode")
            Pattern           = "^(name|zipcode)$"
        }
        $actual = @(Get-DbaRandomizedType @splatTypeFilters)
        $expected = @($expectedAll | Where-Object {
            ($PSItem.Type -match $splatTypeFilters.Pattern -or $PSItem.SubType -match $splatTypeFilters.Pattern) -and
            $PSItem.Type -in $splatTypeFilters.RandomizedType -and
            $PSItem.SubType -in $splatTypeFilters.RandomizedSubType
        })
        $actual.Count | Should -BeGreaterThan 0
        ($actual | ConvertTo-Json -Compress) | Should -BeExactly ($expected | ConvertTo-Json -Compress)
        @(Get-DbaRandomizedType -RandomizedType "Na*").Count | Should -Be 0
        @(Get-DbaRandomizedType -RandomizedType Name -RandomizedSubType ZipCode).Count | Should -Be 0
    }

    It "removes duplicate pattern matches and preserves false-valued filters" -Tag "NativeChecklist:switch-false" {
        $byPattern = @(Get-DbaRandomizedType -Pattern Name)
        $expected = @($expectedAll | Where-Object { $PSItem.Type -match "Name" -or $PSItem.SubType -match "Name" })
        ($byPattern | ConvertTo-Json -Compress) | Should -BeExactly ($expected | ConvertTo-Json -Compress)
        @(Get-DbaRandomizedType -RandomizedType @("") -EnableException:$false).Count | Should -Be $expectedAll.Count
        @(Get-DbaRandomizedType -RandomizedSubType $null -Pattern "").Count | Should -Be $expectedAll.Count
        @(Get-DbaRandomizedType -RandomizedType @("", "")).Count | Should -Be 0
    }

    It "surfaces invalid regular expressions for each input without enabling friendly stops" {
        $referenceErrors = @()
        $splatReferenceMatch = @{
            Property      = "Type"
            Match         = $true
            Value         = "["
            ErrorAction   = "SilentlyContinue"
            ErrorVariable = "referenceErrors"
        }
        $null = $catalog | Where-Object @splatReferenceMatch
        $actualErrors = @()
        $splatInvalidPattern = @{
            Pattern         = "["
            EnableException = $true
            ErrorAction     = "SilentlyContinue"
            ErrorVariable   = "actualErrors"
        }
        $actual = @(Get-DbaRandomizedType @splatInvalidPattern)
        $actual.Count | Should -Be 0
        $actualErrors.Count | Should -Be ($referenceErrors.Count * 2)
        $actualErrors[0].CategoryInfo.Category | Should -Be $referenceErrors[0].CategoryInfo.Category
        $actualErrors[0].Exception.GetType().FullName | Should -BeExactly $referenceErrors[0].Exception.GetType().FullName
        $actualErrors[0].Exception.Message | Should -BeExactly $referenceErrors[0].Exception.Message
        $actualErrors[0].FullyQualifiedErrorId.Split(",")[0] | Should -BeExactly $referenceErrors[0].FullyQualifiedErrorId.Split(",")[0]
    }

    Context "isolated filesystem catalog fixtures" {
        BeforeAll {
            $fixtureRoot = Join-Path $TestConfig.Temp ("randomizer-type-" + [guid]::NewGuid().ToString("N"))
            $fixtureDirectory = Join-Path $fixtureRoot "bin/randomizer"
            $splatFixtureDirectory = @{
                Path     = $fixtureDirectory
                ItemType = "Directory"
                Force    = $true
            }
            $null = New-Item @splatFixtureDirectory
            $fixturePath = Join-Path $fixtureDirectory "en.randomizertypes.csv"
            $fixtureRows = @(
                [pscustomobject]@{ Type = "Zeta"; SubType = "Quoted, value"; RequiredParameter = "A `"quoted`" value" }
                [pscustomobject]@{ Type = "Alpha"; SubType = "Item"; RequiredParameter = "" }
                [pscustomobject]@{ Type = "Alpha"; SubType = "Item"; RequiredParameter = "" }
                [pscustomobject]@{ Type = "Alpha"; SubType = "Item"; RequiredParameter = "Value" }
            )
            $splatFixtureExport = @{
                Path              = $fixturePath
                NoTypeInformation = $true
                Encoding          = "UTF8"
            }
            $fixtureRows | Export-Csv @splatFixtureExport
            # The loader's module root is process-local and set-once. Override only this
            # fixture's process; never rename or change the staged module's shared CSV.
            $moduleRootField = [Dataplat.Dbatools.dbaSystem.SystemHost].GetField("_ModuleBase", "Static,NonPublic")
            $originalModuleRoot = $moduleRootField.GetValue($null)
            $originalScriptRoot = $catalogModule.SessionState.PSVariable.GetValue("script:PSModuleRoot")
        }

        BeforeEach {
            $moduleRootField.SetValue($null, $fixtureRoot)
            $catalogModule.SessionState.PSVariable.Set("script:PSModuleRoot", $fixtureRoot)
        }

        AfterEach {
            $moduleRootField.SetValue($null, $originalModuleRoot)
            $catalogModule.SessionState.PSVariable.Set("script:PSModuleRoot", $originalScriptRoot)
        }

        AfterAll {
            $moduleRootField.SetValue($null, $originalModuleRoot)
            $catalogModule.SessionState.PSVariable.Set("script:PSModuleRoot", $originalScriptRoot)
            $splatFixtureCleanup = @{
                LiteralPath = $fixtureRoot
                Recurse     = $true
                Force       = $true
            }
            Remove-Item @splatFixtureCleanup
        }

        It "reads quoted fields and de-duplicates all three projected values" {
            $actual = @(Get-DbaRandomizedType)
            # Sort-Object on Desktop does not promise a stable order for equal keys.
            # Check the public key order, then compare tied rows by all three values.
            ($actual.Type -join ",") | Should -BeExactly "Alpha,Alpha,Zeta"
            $expected = @($fixtureRows | Select-Object Type, SubType, RequiredParameter -Unique | Sort-Object Type, SubType, RequiredParameter)
            $normalizedActual = @($actual | Sort-Object Type, SubType, RequiredParameter)
            ($normalizedActual | ConvertTo-Json -Compress) | Should -BeExactly ($expected | ConvertTo-Json -Compress)
            $actual.Count | Should -Be 3
        }

        It "warns on a missing catalog and preserves the caller loop" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            $missingRoot = Join-Path $fixtureRoot "missing"
            $moduleRootField.SetValue($null, $missingRoot)
            $catalogModule.SessionState.PSVariable.Set("script:PSModuleRoot", $missingRoot)
            $warnings = @()
            $splatMissingCatalog = @{
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "+warnings"
            }
            $completed = @(
                foreach ($iteration in 1..2) {
                    Get-DbaRandomizedType @splatMissingCatalog
                    $iteration
                }
            )
            ($completed -join ",") | Should -BeExactly "1,2"
            $warnings.Count | Should -Be 2
            $warnings[0].Message | Should -Match "Could not import randomized types"
        }

        It "throws the catalog warning only under EnableException" -Tag "NativeChecklist:enable-exception" {
            $missingRoot = Join-Path $fixtureRoot "missing"
            $moduleRootField.SetValue($null, $missingRoot)
            $catalogModule.SessionState.PSVariable.Set("script:PSModuleRoot", $missingRoot)
            { Get-DbaRandomizedType -EnableException } | Should -Throw "*Could not import randomized types*"
        }
    }
}
