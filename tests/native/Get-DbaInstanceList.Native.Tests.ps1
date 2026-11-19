#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaInstanceList",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- The pinned function declares param () with no pipeline parameter; it only reads the TabExpansion.KnownInstances configuration value.
# NativeChecklist: multi-instance-failure N/A -- The command contacts no instance or computer; it returns the in-process TabExpansion.KnownInstances configuration value.
# NativeChecklist: enable-exception N/A -- The pinned function declares param () under [CmdletBinding()], so it has no -EnableException.
# NativeChecklist: switch-false N/A -- The pinned function declares no switch parameter.
# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads a configuration value.
# NativeChecklist: azure-sqldb N/A -- The command connects to nothing: it reads the in-process dbatools configuration (ConfigurationHost.Configurations), so no SQL Server or Azure SQL Database is involved.

Describe "Instance list pipeline output" -Tag UnitTests {
    BeforeAll {
        $script:instanceListStore = [Dataplat.Dbatools.Configuration.ConfigurationHost]::Configurations
        $script:instanceListKey = "tabexpansion.knowninstances"
        function Get-InstanceListCapturedShape($Captured) {
            $shapes = @()
            for ($shapeIndex = 0; $shapeIndex -lt $Captured.Count; $shapeIndex++) {
                $shapeValue = $Captured[$shapeIndex]
                $shapes += [pscustomobject]@{
                    Type  = $shapeValue.GetType().FullName
                    Value = $shapeValue
                }
            }
            ConvertTo-Json -InputObject $shapes -Depth 5 -Compress
        }
    }

    BeforeEach {
        $script:instanceListFixtureStarted = $false
        $script:instanceListOriginalConfig = $null
        $script:instanceListHadConfig = $script:instanceListStore.TryGetValue($script:instanceListKey, [ref]$script:instanceListOriginalConfig)
        $script:instanceListFixtureStarted = $true
        $removedInstanceListConfig = $null
        $null = $script:instanceListStore.TryRemove($script:instanceListKey, [ref]$removedInstanceListConfig)
        $script:instanceListFixture = New-Object Dataplat.Dbatools.Configuration.Config
        $script:instanceListFixture.Module = "tabexpansion"
        $script:instanceListFixture.Name = "knowninstances"
    }

    AfterEach {
        if ($script:instanceListFixtureStarted) {
            try {
                $removedInstanceListFixture = $null
                $null = $script:instanceListStore.TryRemove($script:instanceListKey, [ref]$removedInstanceListFixture)
            } finally {
                if ($script:instanceListHadConfig) {
                    $script:instanceListStore[$script:instanceListKey] = $script:instanceListOriginalConfig
                }
            }
            $restoredInstanceListConfig = $null
            $restoredInstanceListPresent = $script:instanceListStore.TryGetValue($script:instanceListKey, [ref]$restoredInstanceListConfig)
            if ($restoredInstanceListPresent -ne $script:instanceListHadConfig -or ($script:instanceListHadConfig -and -not [object]::ReferenceEquals($script:instanceListOriginalConfig, $restoredInstanceListConfig))) {
                throw "Instance list original configuration reference was not restored"
            }
        }
    }

    Context "Missing setting" {
        It "emits zero pipeline records for a missing setting" {
            $missingCaptured = New-Object "System.Collections.Generic.List[object]"
            Get-DbaInstanceList | ForEach-Object { $missingCaptured.Add($PSItem) }
            $missingCaptured.Count | Should -Be 0 -Because ("captured pipeline shape was " + (Get-InstanceListCapturedShape $missingCaptured))
        }
    }

    Context "Empty setting" {
        BeforeEach {
            $script:instanceListFixture.Value = [object[]]@()
            $script:instanceListStore[$script:instanceListKey] = $script:instanceListFixture
        }
        It "emits zero pipeline records for an empty setting" {
            $emptyCaptured = New-Object "System.Collections.Generic.List[object]"
            Get-DbaInstanceList | ForEach-Object { $emptyCaptured.Add($PSItem) }
            $emptyCaptured.Count | Should -Be 0 -Because ("captured pipeline shape was " + (Get-InstanceListCapturedShape $emptyCaptured))
        }
    }

    Context "Two configured strings" {
        BeforeEach {
            $script:instanceListFixture.Value = [object[]]@("native-list-alpha", "native-list-beta")
            $script:instanceListStore[$script:instanceListKey] = $script:instanceListFixture
        }
        It "emits two separate string records in configured order" {
            $twoCaptured = New-Object "System.Collections.Generic.List[object]"
            Get-DbaInstanceList | ForEach-Object { $twoCaptured.Add($PSItem) }
            $twoCaptured.Count | Should -Be 2 -Because ("captured pipeline shape was " + (Get-InstanceListCapturedShape $twoCaptured))
            $twoCaptured[0].GetType().FullName | Should -BeExactly "System.String"
            $twoCaptured[1].GetType().FullName | Should -BeExactly "System.String"
            $twoCaptured[0] | Should -BeExactly "native-list-alpha"
            $twoCaptured[1] | Should -BeExactly "native-list-beta"
        }
    }

    Context "One configured string" {
        BeforeEach {
            $script:instanceListFixture.Value = "native-list-single"
            $script:instanceListStore[$script:instanceListKey] = $script:instanceListFixture
        }
        It "emits the whole string as one record" {
            $singleCaptured = New-Object "System.Collections.Generic.List[object]"
            Get-DbaInstanceList | ForEach-Object { $singleCaptured.Add($PSItem) }
            $singleCaptured.Count | Should -Be 1 -Because ("captured pipeline shape was " + (Get-InstanceListCapturedShape $singleCaptured))
            $singleCaptured[0].GetType().FullName | Should -BeExactly "System.String"
            $singleCaptured[0] | Should -BeExactly "native-list-single"
        }
    }
}
