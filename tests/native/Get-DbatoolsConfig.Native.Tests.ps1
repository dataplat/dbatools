#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbatoolsConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native configuration query filters" {
    BeforeAll {
        $script:configQueryPrefix = "nativequery" + [Guid]::NewGuid().ToString("N")
        $script:configQueryItems = @()
        foreach ($entry in @(
            @{ Module = "b"; Name = "alpha"; Hidden = $false },
            @{ Module = "a"; Name = "zebra"; Hidden = $false },
            @{ Module = "a"; Name = "alpha"; Hidden = $false },
            @{ Module = "a"; Name = "hidden"; Hidden = $true }
        )) {
            $configQueryItem = New-Object Dataplat.Dbatools.Configuration.Config
            $configQueryItem.Module = $script:configQueryPrefix + $entry.Module
            $configQueryItem.Name = $entry.Name
            $configQueryItem.Hidden = $entry.Hidden
            $configQueryItem.Value = 42
            [Dataplat.Dbatools.Configuration.ConfigurationHost]::Configurations[$configQueryItem.FullName] = $configQueryItem
            $script:configQueryItems += $configQueryItem
        }
    }
    AfterAll {
        foreach ($configQueryItem in $script:configQueryItems) {
            $removedQueryItem = $null
            $null = [Dataplat.Dbatools.Configuration.ConfigurationHost]::Configurations.TryRemove($configQueryItem.FullName, [ref]$removedQueryItem)
        }
    }

    It "matches full-name wildcards and sorts by module then name" {
        $queryResults = @(Get-DbatoolsConfig -FullName ($script:configQueryPrefix.ToUpperInvariant() + "*"))
        $queryResults.Count | Should -Be 3
        $queryResults[0].FullName | Should -BeExactly ($script:configQueryPrefix + "a.alpha")
        $queryResults[1].FullName | Should -BeExactly ($script:configQueryPrefix + "a.zebra")
        $queryResults[2].FullName | Should -BeExactly ($script:configQueryPrefix + "b.alpha")
    }

    It "combines module and name filters while retaining configuration identity" {
        $queryResults = @(Get-DbatoolsConfig -Module ($script:configQueryPrefix.ToUpperInvariant() + "A") -Name "AL*")
        $queryResults.Count | Should -Be 1
        [object]::ReferenceEquals($queryResults[0], $script:configQueryItems[2]) | Should -BeTrue
        $queryResults[0].Value | Should -Be 42
        @(Get-DbatoolsConfig -Module ($script:configQueryPrefix + "a") -Name "missing*").Count | Should -Be 0
    }

    It "includes hidden values only when Force is true in either parameter set" {
        $fullNameFilter = $script:configQueryPrefix + "a.hidden"
        $moduleFilter = $script:configQueryPrefix + "a"
        @(Get-DbatoolsConfig -FullName $fullNameFilter).Count | Should -Be 0
        @(Get-DbatoolsConfig -FullName $fullNameFilter -Force:$false).Count | Should -Be 0
        @(Get-DbatoolsConfig -Module $moduleFilter -Name "hidden" -Force:$false).Count | Should -Be 0
        $fullNameResult = @(Get-DbatoolsConfig -FullName $fullNameFilter -Force)
        $moduleResult = @(Get-DbatoolsConfig -Module $moduleFilter -Name "hidden" -Force)
        $fullNameResult.Count | Should -Be 1
        $moduleResult.Count | Should -Be 1
        [object]::ReferenceEquals($fullNameResult[0], $script:configQueryItems[3]) | Should -BeTrue
        [object]::ReferenceEquals($moduleResult[0], $script:configQueryItems[3]) | Should -BeTrue
    }
}
