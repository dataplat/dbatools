#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaCredential",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Credential",
                "Destination",
                "DestinationSqlCredential",
                "Name",
                "ExcludeName",
                "Identity",
                "ExcludeIdentity",
                "ExcludePassword",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    <#
        Credentials that use a crypto provider (Ref: https://github.com/dataplat/dbatools/issues/7896)
        are NOT covered here, deliberately. Neither copy instance has an EKM provider registered, so
        those legs could only ever have been Its that ran and asserted nothing. Restore them once a
        provider exists on both instances - the branch they cover is the ProviderName lookup in the
        copy loop, which throws when the provider is missing or disabled on the destination.

        Follow these steps to configure the local machine to run the crypto provider tests.

        1. Run these SQL commands on the InstanceSingle and instance3 servers:

        -- Enable advanced options.
        USE master;
        GO
        sp_configure 'show advanced options', 1;
        GO
        RECONFIGURE;
        GO
        -- Enable EKM provider
        sp_configure 'EKM provider enabled', 1;
        GO
        RECONFIGURE;

        2. Install https://www.microsoft.com/en-us/download/details.aspx?id=45344 on the InstanceSingle and instance3 servers.

        3. Run these SQL commands on the InstanceSingle and instance3 servers:

        CREATE CRYPTOGRAPHIC PROVIDER dbatoolsci_AKV FROM FILE = 'C:\github\appveyor-lab\keytests\ekm\Microsoft.AzureKeyVaultService.EKM.dll'
    #>
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Explain what needs to be set up for the test:
        # A credential pairs a name with a Windows identity and a password, so the source host needs
        # real local accounts to point the identities at. Two accounts with DIFFERENT passwords are
        # created because the command decrypts the whole credential set once and then looks each
        # password up per credential inside the copy loop - a leak there would hand the second
        # credential the first one's password, and identity assertions alone cannot see that.

        # The command refuses to run when the module-scope $script:isWindows flag is not true. That
        # flag is set while dbatools.psm1 executes, but a Pester run reaches the module with the
        # flag unset, so every leg below would take the refusal branch and assert nothing. Pin it
        # to the real platform value for the duration of the suite and put the original back in
        # AfterAll. The refusal branch itself is covered by its own Context, which flips the same
        # flag the other way - the established idiom for this guard.
        $originalIsWindows = InModuleScope -ModuleName dbatools -ScriptBlock { $script:isWindows }
        InModuleScope -ModuleName dbatools -ScriptBlock { $script:isWindows = $true }

        # Set variables. They are available in all the It blocks.
        $suffix = Get-Random
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2

        $firstLogin = "dbatoolsci_first_$suffix"
        $secondLogin = "dbatoolsci_second_$suffix"
        $firstPlaintext = "FirstPassword1!"
        $secondPlaintext = "SecondPassword2!"
        $firstCredential = "dbatoolsci-cred-first-$suffix"
        $secondCredential = "dbatoolsci-cred-second-$suffix"
        $excludeCredential = "dbatoolsci-cred-exclude-$suffix"
        $whatIfCredential = "dbatoolsci-cred-whatif-$suffix"
        $allCredentials = @($firstCredential, $secondCredential, $excludeCredential, $whatIfCredential)
        $allLogins = @($firstLogin, $secondLogin)

        # Create the objects.
        $splatFirstAccount = @{
            ComputerName = $TestConfig.InstanceCopy1
            ArgumentList = $firstLogin, $firstPlaintext
            ScriptBlock  = { net user $args[0] $args[1] /add *>&1 }
        }
        $null = Invoke-Command2 @splatFirstAccount

        $splatSecondAccount = @{
            ComputerName = $TestConfig.InstanceCopy1
            ArgumentList = $secondLogin, $secondPlaintext
            ScriptBlock  = { net user $args[0] $args[1] /add *>&1 }
        }
        $null = Invoke-Command2 @splatSecondAccount

        $splatFirstCredential = @{
            SqlInstance    = $sourceServer
            Name           = $firstCredential
            Identity       = $firstLogin
            SecurePassword = (ConvertTo-SecureString $firstPlaintext -AsPlainText -Force)
        }
        $null = New-DbaCredential @splatFirstCredential

        $splatSecondCredential = @{
            SqlInstance    = $sourceServer
            Name           = $secondCredential
            Identity       = $secondLogin
            SecurePassword = (ConvertTo-SecureString $secondPlaintext -AsPlainText -Force)
        }
        $null = New-DbaCredential @splatSecondCredential

        $splatExcludeCredential = @{
            SqlInstance    = $sourceServer
            Name           = $excludeCredential
            Identity       = $secondLogin
            SecurePassword = (ConvertTo-SecureString $secondPlaintext -AsPlainText -Force)
        }
        $null = New-DbaCredential @splatExcludeCredential

        $splatWhatIfCredential = @{
            SqlInstance    = $sourceServer
            Name           = $whatIfCredential
            Identity       = $firstLogin
            SecurePassword = (ConvertTo-SecureString $firstPlaintext -AsPlainText -Force)
        }
        $null = New-DbaCredential @splatWhatIfCredential

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $leftovers = Get-DbaCredential -SqlInstance $sourceServer, $destServer -Name $allCredentials -EnableException:$false
        if ($leftovers) {
            $null = $leftovers | Remove-DbaCredential -EnableException:$false
        }

        foreach ($login in $allLogins) {
            $splatRemoveAccount = @{
                ComputerName = $TestConfig.InstanceCopy1
                ArgumentList = $login
                ScriptBlock  = { net user $args /delete *>&1 }
            }
            $null = Invoke-Command2 @splatRemoveAccount
        }

        $splatRestorePlatform = @{
            ModuleName  = "dbatools"
            Parameters  = @{ OriginalValue = $originalIsWindows }
            ScriptBlock = { $script:isWindows = $OriginalValue }
        }
        InModuleScope @splatRestorePlatform

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When previewing the copy with WhatIf" {
        BeforeAll {
            $splatWhatIf = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                Name            = $whatIfCredential
                WhatIf          = $true
                WarningVariable = "whatIfWarning"
                WarningAction   = "SilentlyContinue"
            }
            $whatIfResults = @(Copy-DbaCredential @splatWhatIf)
            $destServer.Credentials.Refresh()
        }

        It "Should emit no result objects because every status is gated by ShouldProcess" {
            $whatIfResults.Count | Should -Be 0
        }

        It "Should not create the credential on the destination" {
            $destServer.Credentials.Name | Should -Not -Contain $whatIfCredential
        }
    }

    Context "When copying several credentials in one call" {
        BeforeAll {
            $splatCopy = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                Name            = $firstCredential, $secondCredential
                WarningVariable = "copyWarning"
                WarningAction   = "SilentlyContinue"
            }
            $copyResults = @(Copy-DbaCredential @splatCopy)
            $destServer.Credentials.Refresh()

            # The password is not readable through any supported surface, so it is recovered from the
            # destination the same way the command recovers it from the source: a dedicated admin
            # connection plus the service master key. This is the only assertion that can see a
            # cross-record password leak, which is why it is worth the extra DAC.
            $destinationDac = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -DedicatedAdminConnection -WarningAction SilentlyContinue
            $splatDecrypt = @{
                ModuleName  = "dbatools"
                Parameters  = @{ DacServer = $destinationDac }
                ScriptBlock = { Get-DecryptedObject -SqlInstance $DacServer -Type Credential -EnableException }
            }
            $decryptedOnDestination = InModuleScope @splatDecrypt
            $null = $destinationDac | Disconnect-DbaInstance

            $firstOnDestination = $decryptedOnDestination | Where-Object { $PSItem.Name -eq $firstCredential }
            $secondOnDestination = $decryptedOnDestination | Where-Object { $PSItem.Name -eq $secondCredential }
        }

        It "Should report one successful result per credential" {
            $copyResults.Count | Should -Be 2
            $copyResults.Status | Should -Be @("Successful", "Successful")
            $copyResults.Type | Should -Be @("Credential", "Credential")
            $copyResults.Name | Should -Contain $firstCredential
            $copyResults.Name | Should -Contain $secondCredential
        }

        It "Should create both credentials on the destination with their own identities" {
            $destServer.Credentials.Name | Should -Contain $firstCredential
            $destServer.Credentials.Name | Should -Contain $secondCredential
            $destServer.Credentials[$firstCredential].Identity | Should -Be $firstLogin
            $destServer.Credentials[$secondCredential].Identity | Should -Be $secondLogin
        }

        It "Should carry each credential's own password across, not the first one's" {
            $firstOnDestination.Password | Should -Be $firstPlaintext
            $secondOnDestination.Password | Should -Be $secondPlaintext
        }

        It "Should skip a credential that already exists when Force is not used" {
            $splatSkip = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Name        = $firstCredential
            }
            $skipResults = Copy-DbaCredential @splatSkip
            $skipResults.Status | Should -Be "Skipping"
            $skipResults.Notes | Should -Be "Already exists on destination"
        }

        It "Should drop and recreate an existing credential when Force is used" {
            $splatForce = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Name        = $firstCredential
                Force       = $true
            }
            $forceResults = Copy-DbaCredential @splatForce
            $forceResults.Status | Should -Be "Successful"

            $destServer.Credentials.Refresh()
            $destServer.Credentials[$firstCredential].Identity | Should -Be $firstLogin
        }
    }

    Context "When excluding passwords" {
        BeforeAll {
            $splatExclude = @{
                Source          = $TestConfig.InstanceCopy1
                Destination     = $TestConfig.InstanceCopy2
                Name            = $excludeCredential
                ExcludePassword = $true
                WarningVariable = "excludeWarning"
                WarningAction   = "SilentlyContinue"
            }
            $excludeResults = Copy-DbaCredential @splatExclude
            $destServer.Credentials.Refresh()
        }

        It "Should copy the definition over the no-DAC path" {
            $excludeResults.Status | Should -Be "Successful"
            $destServer.Credentials.Name | Should -Contain $excludeCredential
            $destServer.Credentials[$excludeCredential].Identity | Should -Be $secondLogin
        }
    }

    Context "When resolving the command name in a cold shell" {
        BeforeAll {
            # Every other leg runs in a session that imported dbatools long before Pester started,
            # so none of them can tell the binary cmdlet apart from the retired script function -
            # whichever got there first answers to the name. This leg starts a shell of the same
            # edition that has imported nothing, loads the module the way a consumer does, and asks
            # what the name resolves to. dbatools.psm1 is the import under test on purpose: it is
            # the loader that pulls the satellite in by path, and importing the manifest by name
            # cannot work in a dev tree because the satellites are not on PSModulePath.
            $moduleBase = @(Get-Module -Name dbatools)[0].ModuleBase
            $shellPath = (Get-Process -Id $PID).Path
            $probePath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci-resolve-$(Get-Random).ps1"

            # Get-Command -All so a retired function shadowing the cmdlet shows up as a second
            # entry rather than silently winning; the count is what proves it is not there.
            $probeBody = @"
Import-Module -Name "$moduleBase\dbatools.psm1" -DisableNameChecking
`$resolved = Get-Command -Name Copy-DbaCredential -ErrorAction SilentlyContinue
`$allResolved = @(Get-Command -Name Copy-DbaCredential -All -ErrorAction SilentlyContinue)
`$functionCount = @(`$allResolved | Where-Object { `$PSItem.CommandType -eq "Function" }).Count
`$satelliteLoaded = [bool](Get-Module -Name dbatools.migration)
"RESOLVED|`$(`$resolved.CommandType)|`$(`$resolved.ModuleName)|`$functionCount|`$satelliteLoaded"
"@
            Set-Content -Path $probePath -Value $probeBody -Encoding UTF8

            $probeOutput = & $shellPath -NoProfile -NonInteractive -File $probePath 2>&1
            $probeFields = @("$(@($probeOutput | Where-Object { "$PSItem" -like "RESOLVED|*" })[0])" -split "\|")
        }

        AfterAll {
            Remove-Item -Path $probePath -ErrorAction SilentlyContinue
        }

        It "Should resolve to the binary cmdlet shipped by dbatools.migration" {
            $probeFields[1] | Should -Be "Cmdlet"
            $probeFields[2] | Should -Be "dbatools.migration"
        }

        It "Should load the satellite and leave no retired function shadowing the name" {
            $probeFields[4] | Should -Be "True"
            $probeFields[3] | Should -Be "0"
        }
    }

    Context "When the host is not Windows" {
        It "Should warn and do nothing" {
            # Pinned by flipping the module-scope platform flag rather than by mocking the
            # connection, and restored in a finally so it cannot leak into the other contexts.
            InModuleScope -ModuleName dbatools -ScriptBlock {
                $savedIsWindows = $script:isWindows
                try {
                    $script:isWindows = $false
                    $splatNonWindows = @{
                        Source          = "dbatoolsci-src"
                        Destination     = "dbatoolsci-dst"
                        WarningVariable = "nonWindowsWarning"
                        WarningAction   = "SilentlyContinue"
                    }
                    $nonWindowsResults = @(Copy-DbaCredential @splatNonWindows)
                    $nonWindowsResults.Count | Should -Be 0

                    # strip the bracketed [timestamp]/[function] prefix added by Write-Message
                    $payloads = $nonWindowsWarning | ForEach-Object { $PSItem.Message -replace "^(\[[^\]]*\]\s*)+", "" }
                    $payloads | Should -Contain "Copy-DbaCredential is only supported on Windows"
                } finally {
                    $script:isWindows = $savedIsWindows
                }
            }
        }
    }
}
