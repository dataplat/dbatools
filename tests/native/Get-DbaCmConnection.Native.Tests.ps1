#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaCmConnection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: azure-sqldb N/A -- The command connects to nothing: it filters the in-process dbatools connection cache (ConnectionHost.Connections), so no SQL Server or Azure SQL Database is involved.
# NativeChecklist: multi-instance-failure N/A -- No instance or computer is contacted; a computer name that is not cached simply matches nothing, tested below.
# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads the connection cache.

Describe "Get-DbaCmConnection native" -Tag IntegrationTests {
    BeforeAll {
        $random = Get-Random
        # Unique cache entries for this run; the cache lives in this process only.
        $nameA = "dbatoolsci-cma-$random"
        $nameB = "dbatoolsci-cmb-$random"
        $nameC = "dbatoolsci-cmc-$random"
        $userName = "dbatoolsci_cmuser_$random"
        $password = ConvertTo-SecureString -String "dbatools.IO-$random" -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential -ArgumentList $userName, $password

        $null = New-DbaCmConnection -ComputerName $nameA -EnableException
        $null = New-DbaCmConnection -ComputerName $nameB -Credential $credential -EnableException
        $null = New-DbaCmConnection -ComputerName $nameC -UseWindowsCredentials -EnableException
        $pattern = "dbatoolsci-cm?-$random"
    }

    AfterAll {
        $null = Remove-DbaCmConnection -ComputerName $nameA, $nameB, $nameC -Confirm:$false
    }

    Context "Computer name filter" {
        It "returns the cached connections a computer name wildcard matches, case-insensitively" {
            $results = @(Get-DbaCmConnection -ComputerName $pattern.ToUpperInvariant())
            $results.Count | Should -Be 3
            $results[0] | Should -BeOfType [Dataplat.Dbatools.Connection.ManagementConnection]
            ($results.ComputerName | Sort-Object) | Should -Be @($nameA, $nameB, $nameC)
        }

        It "returns the connection named exactly, through the Filter alias and by position" {
            @(Get-DbaCmConnection -Filter $nameB).ComputerName | Should -Be $nameB
            @(Get-DbaCmConnection $nameB).ComputerName | Should -Be $nameB
        }

        It "returns nothing for a computer name that is not cached" {
            @(Get-DbaCmConnection -ComputerName "dbatoolsci-cmnone-$random").Count | Should -Be 0
        }

        It "searches once per name, so a connection two names match is returned twice, as the pinned loop does" {
            $results = @(Get-DbaCmConnection -ComputerName $pattern, $nameA)
            @($results | Where-Object ComputerName -eq $nameA).Count | Should -Be 2
        }
    }

    Context "User name filter" {
        It "matches the stored credential's user name; connections without credentials do not match a user pattern" {
            $results = @(Get-DbaCmConnection -ComputerName $pattern -UserName "*CMUSER_$random")
            $results.ComputerName | Should -Be $nameB
            $results.Credentials.UserName | Should -Be $userName
        }

        It "includes connections without stored credentials under the default user name filter" {
            $results = @(Get-DbaCmConnection -ComputerName $nameA, $nameC)
            ($results.ComputerName | Sort-Object) | Should -Be @($nameA, $nameC)
            $results | ForEach-Object { $PSItem.Credentials | Should -BeNullOrEmpty }
        }
    }

    Context "Pipeline input" -Tag NativeChecklist:pipeline-multiple {
        It "searches every piped computer name, in order" {
            $results = @($nameC, $nameA | Get-DbaCmConnection)
            $results.ComputerName | Should -Be @($nameC, $nameA)
        }
    }

    Context "Removing returned connections downstream" {
        BeforeAll {
            $removeNames = @("dbatoolsci-cmrd-$random", "dbatoolsci-cmre-$random", "dbatoolsci-cmrf-$random")
            foreach ($removeName in $removeNames) {
                $null = New-DbaCmConnection -ComputerName $removeName -EnableException
            }
            $removePattern = "dbatoolsci-cmr?-$random"
        }

        AfterAll {
            $null = Remove-DbaCmConnection -ComputerName $removeNames -Confirm:$false
        }

        It "finishes the search before emitting, so a downstream Remove-DbaCmConnection removes every match, as the pinned parenthesized pipeline does" {
            @(Get-DbaCmConnection -ComputerName $removePattern).Count | Should -Be 3
            { Get-DbaCmConnection -ComputerName $removePattern | ForEach-Object { Remove-DbaCmConnection -ComputerName $PSItem.ComputerName -Confirm:$false } } | Should -Not -Throw
            @(Get-DbaCmConnection -ComputerName $removePattern).Count | Should -Be 0
            @(Get-DbaCmConnection -ComputerName $pattern).Count | Should -Be 3
        }
    }

    Context "Messages" {
        It "writes the pinned verbose messages once for the call and once per searched name" {
            $streams = @(Get-DbaCmConnection -ComputerName $nameA, $nameB -UserName "*" -Verbose 4>&1)
            $messages = @($streams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            # Default parameter values from the test configuration may add keys, so each named key is checked on its own.
            $boundMessages = @($messages | Where-Object { $PSItem -match "Bound parameters: " })
            $boundMessages.Count | Should -Be 1
            $boundMessages[0] | Should -Match "Bound parameters: .*\bComputerName\b"
            $boundMessages[0] | Should -Match "Bound parameters: .*\bUserName\b"
            $boundMessages[0] | Should -Match "Bound parameters: .*\bVerbose\b"
            @($messages | Where-Object { $PSItem -match ([regex]::Escape("Processing search. ComputerName: '$nameA' | Username: '*'") + "$") }).Count | Should -Be 1
            @($messages | Where-Object { $PSItem -match ([regex]::Escape("Processing search. ComputerName: '$nameB' | Username: '*'") + "$") }).Count | Should -Be 1
            @($streams | Where-Object { $PSItem -is [Dataplat.Dbatools.Connection.ManagementConnection] }).Count | Should -Be 2
        }
    }

    Context "EnableException" -Tag NativeChecklist:enable-exception {
        It "returns the same connections under -EnableException, which the pinned function never uses to stop" {
            $results = @(Get-DbaCmConnection -ComputerName $pattern -EnableException)
            ($results.ComputerName | Sort-Object) | Should -Be @($nameA, $nameB, $nameC)
        }

        It "returns the same connections for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            $results = @(Get-DbaCmConnection -ComputerName $pattern -EnableException:$false)
            ($results.ComputerName | Sort-Object) | Should -Be @($nameA, $nameB, $nameC)
        }
    }
}
