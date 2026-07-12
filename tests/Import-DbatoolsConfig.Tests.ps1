#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbatoolsConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "ModuleName",
                "ModuleVersion",
                "Scope",
                "IncludeFilter",
                "ExcludeFilter",
                "Peek",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (TA-028): pure config-store + local-file compute, CI-safe.
    BeforeAll {
        $configSuffix = "ta028$(Get-Random)"
        $configDir = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $configDir -ItemType Directory
        $jsonPath = "$configDir\import.json"
        $jsonBody = "[{`"FullName`":`"dbatoolsci.$configSuffix.alpha`",`"Version`":1,`"Data`":`"alphavalue`"},{`"FullName`":`"dbatoolsci.$configSuffix.beta`",`"Version`":1,`"Data`":`"betavalue`"}]"
        [System.IO.File]::WriteAllText($jsonPath, $jsonBody)
    }

    AfterAll {
        Remove-Item -Path $configDir -Recurse -ErrorAction SilentlyContinue
    }

    Context "Peek" {
        It "returns the would-be imports without applying them" {
            $results = @(Import-DbatoolsConfig -Path $jsonPath -Peek)
            $results.Count | Should -Be 2
            $results[0].FullName | Should -Be "dbatoolsci.$configSuffix.alpha"
            $results[0].Value | Should -Be "alphavalue"
            $results[0].KeepPersisted | Should -Be $false
            $results[0].PSObject.Properties.Name -join "," | Should -Be "FullName,Value,Type,KeepPersisted,Enforced,Policy"
            Get-DbatoolsConfigValue -FullName "dbatoolsci.$configSuffix.alpha" | Should -BeNullOrEmpty
        }

        It "honors IncludeFilter and ExcludeFilter" {
            $included = @(Import-DbatoolsConfig -Path $jsonPath -Peek -IncludeFilter "*alpha")
            $included.Count | Should -Be 1
            $included[0].FullName | Should -Be "dbatoolsci.$configSuffix.alpha"

            $excluded = @(Import-DbatoolsConfig -Path $jsonPath -Peek -ExcludeFilter "*alpha")
            $excluded.Count | Should -Be 1
            $excluded[0].FullName | Should -Be "dbatoolsci.$configSuffix.beta"

            $both = @(Import-DbatoolsConfig -Path $jsonPath -Peek -IncludeFilter "dbatoolsci.*" -ExcludeFilter "*beta")
            $both.Count | Should -Be 1
            $both[0].FullName | Should -Be "dbatoolsci.$configSuffix.alpha"
        }
    }

    Context "Applying imports" {
        It "imports from a file into the configuration store" {
            $results = Import-DbatoolsConfig -Path $jsonPath
            $results | Should -BeNullOrEmpty
            Get-DbatoolsConfigValue -FullName "dbatoolsci.$configSuffix.alpha" | Should -Be "alphavalue"
            Get-DbatoolsConfigValue -FullName "dbatoolsci.$configSuffix.beta" | Should -Be "betavalue"
        }

        It "imports from a raw json string" {
            $rawSuffix = "ta028raw$(Get-Random)"
            $rawJson = "[{`"FullName`":`"dbatoolsci.$rawSuffix.gamma`",`"Version`":1,`"Data`":`"gammavalue`"}]"
            $null = Import-DbatoolsConfig -Path $rawJson
            Get-DbatoolsConfigValue -FullName "dbatoolsci.$rawSuffix.gamma" | Should -Be "gammavalue"
        }

        It "accepts pipeline input" {
            $pipeSuffix = "ta028pipe$(Get-Random)"
            $pipeJson = "[{`"FullName`":`"dbatoolsci.$pipeSuffix.delta`",`"Version`":1,`"Data`":`"deltavalue`"}]"
            $pipeJson | Import-DbatoolsConfig
            Get-DbatoolsConfigValue -FullName "dbatoolsci.$pipeSuffix.delta" | Should -Be "deltavalue"
        }
    }

    Context "Failure modes" {
        It "warns and continues on unparseable input" {
            Import-DbatoolsConfig -Path "this is not json and not a file" -WarningVariable WarnVar -WarningAction SilentlyContinue
            # Two warnings: the nested Resolve-DbaPath failure bubbles first, then the import failure.
            $WarnVar.Count | Should -Be 2
            $WarnVar[0] | Should -BeLike "*Failed to resolve path*"
            $WarnVar[1] | Should -BeLike "*Failed to import*"
        }

        It "throws with EnableException on unparseable input" {
            { Import-DbatoolsConfig -Path "this is not json and not a file" -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }
}