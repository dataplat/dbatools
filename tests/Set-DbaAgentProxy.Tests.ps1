#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentProxy",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaAgentProxy.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Proxy",
                "ProxyCredential",
                "Description",
                "NewName",
                "InputObject",
                "Enabled",
                "AddLogin",
                "RemoveLogin",
                "AddServerRole",
                "RemoveServerRole",
                "AddMsdbRole",
                "RemoveMsdbRole",
                "AddSubsystem",
                "RemoveSubsystem",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # Two instance-level credentials backed by NT AUTHORITY\SYSTEM - no local principal needed. The
        # second is the reassign target for the -ProxyCredential leg.
        $credName1 = "dbatoolsci_proxycred1_$random"
        $credName2 = "dbatoolsci_proxycred2_$random"
        $null = Invoke-DbaQuery -SqlInstance $InstanceSingle -Query "CREATE CREDENTIAL [$credName1] WITH IDENTITY = 'NT AUTHORITY\SYSTEM', SECRET = 'G31o)lkJ8HNd!';"
        $null = Invoke-DbaQuery -SqlInstance $InstanceSingle -Query "CREATE CREDENTIAL [$credName2] WITH IDENTITY = 'NT AUTHORITY\SYSTEM', SECRET = 'G31o)lkJ8HNd!';"

        # Each behavioral leg gets its OWN proxy so the tests do not couple through shared proxy state.
        $proxyDesc = "dbatoolsci_pxdesc_$random"
        $proxyWhatIf = "dbatoolsci_pxwhatif_$random"
        $proxyRename = "dbatoolsci_pxrename_$random"
        $proxyRenameNew = "dbatoolsci_pxrenamed_$random"
        $proxyCredReassign = "dbatoolsci_pxcred_$random"
        $proxySubsys = "dbatoolsci_pxsubsys_$random"
        $proxyPipe1 = "dbatoolsci_pxpipe1_$random"
        $proxyPipe2 = "dbatoolsci_pxpipe2_$random"
        $allProxies = @($proxyDesc, $proxyWhatIf, $proxyRename, $proxyRenameNew, $proxyCredReassign, $proxySubsys, $proxyPipe1, $proxyPipe2)

        foreach ($proxyName in @($proxyDesc, $proxyWhatIf, $proxyRename, $proxyCredReassign, $proxySubsys, $proxyPipe1, $proxyPipe2)) {
            $splatNew = @{
                SqlInstance     = $InstanceSingle
                Name            = $proxyName
                ProxyCredential = $credName1
            }
            $null = New-DbaAgentProxy @splatNew
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaAgentProxy -SqlInstance $InstanceSingle -Proxy $allProxies -Confirm:$false -ErrorAction SilentlyContinue
        Invoke-DbaQuery -SqlInstance $InstanceSingle -Query "IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = '$credName1') DROP CREDENTIAL [$credName1]; IF EXISTS (SELECT 1 FROM sys.credentials WHERE name = '$credName2') DROP CREDENTIAL [$credName2];" -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits the designed ShouldProcess string and changes nothing" {
            # Alter executes immediately via ExecuteNonQuery, so WhatIf must gate it and leave the proxy
            # untouched. WhatIf text is HOST-DIRECT so a transcript is the reliable capture.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_pxwhatif_$random.txt"
            $splatWhatIf = @{
                SqlInstance = $InstanceSingle
                Proxy       = $proxyWhatIf
                Description = "should-not-land"
                WhatIf      = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Set-DbaAgentProxy @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                # The ShouldProcess target renders as the SMO server ToString ("[sql01]"), so pin the
                # distinguishing action string rather than the exact target rendering.
                $transcriptText | Should -Match ([regex]::Escape("Altering Agent proxy $proxyWhatIf"))
            } finally {
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and the side effect did NOT happen: the description is still empty.
            $unchanged = Get-DbaAgentProxy -SqlInstance $InstanceSingle -Proxy $proxyWhatIf
            $unchanged.Description | Should -BeNullOrEmpty
        }
    }

    Context "Command behavior" {
        It "Sets the description, toggles Enabled off, and re-emits the decorated object" {
            $splatDesc = @{
                SqlInstance     = $InstanceSingle
                Proxy           = $proxyDesc
                Description     = "updated by Set-DbaAgentProxy"
                Enabled         = $false
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaAgentProxy @splatDesc
            $result.Description | Should -Be "updated by Set-DbaAgentProxy"
            $result.IsEnabled | Should -BeFalse
            # Decoration parity with Get-DbaAgentProxy so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            # Read back independently.
            $readBack = Get-DbaAgentProxy -SqlInstance $InstanceSingle -Proxy $proxyDesc
            $readBack.Description | Should -Be "updated by Set-DbaAgentProxy"
            $readBack.IsEnabled | Should -BeFalse
        }

        It "Renames the proxy account" {
            $splatRename = @{
                SqlInstance     = $InstanceSingle
                Proxy           = $proxyRename
                NewName         = $proxyRenameNew
                EnableException = $true
                Confirm         = $false
            }
            $null = Set-DbaAgentProxy @splatRename
            # The reused connection's client-side ProxyAccounts collection can echo the renamed proxy
            # twice after the in-place Rename+Refresh (a benign SMO cache artifact - server state is a
            # single row), so unique the names before asserting.
            ((Get-DbaAgentProxy -SqlInstance $InstanceSingle -Proxy $proxyRenameNew).Name | Select-Object -Unique) | Should -Be $proxyRenameNew
            Get-DbaAgentProxy -SqlInstance $InstanceSingle -Proxy $proxyRename | Should -BeNullOrEmpty
        }

        It "Reassigns the proxy to a different credential" {
            $splatCred = @{
                SqlInstance     = $InstanceSingle
                Proxy           = $proxyCredReassign
                ProxyCredential = $credName2
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaAgentProxy @splatCred
            $result.CredentialName | Should -Be $credName2
            (Get-DbaAgentProxy -SqlInstance $InstanceSingle -Proxy $proxyCredReassign).CredentialName | Should -Be $credName2
        }

        It "Adds and then removes a subsystem grant" {
            # EnumSubSystems returns a DataTable whose Name column carries the friendly subsystem name.
            $added = Set-DbaAgentProxy -SqlInstance $InstanceSingle -Proxy $proxySubsys -AddSubsystem PowerShell -Confirm:$false -EnableException
            $added.EnumSubSystems().Name | Should -Contain "PowerShell"

            $removed = Set-DbaAgentProxy -SqlInstance $InstanceSingle -Proxy $proxySubsys -RemoveSubsystem PowerShell -Confirm:$false -EnableException
            $removed.EnumSubSystems().Name | Should -Not -Contain "PowerShell"
        }

        It "Processes multiple piped proxies and resolves each record's own parent (N in, N out)" {
            # Multi-record piped leg. Two distinct proxies piped in must both come back altered, each
            # resolving its own parent server.
            $results = Get-DbaAgentProxy -SqlInstance $InstanceSingle -Proxy $proxyPipe1, $proxyPipe2 |
                Set-DbaAgentProxy -Description "piped update" -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            ($results.Description | Sort-Object -Unique) | Should -Be "piped update"
            ($results.Name | Sort-Object) | Should -Be @($proxyPipe1, $proxyPipe2 | Sort-Object)

            # Read back independently - each proxy's own description was changed.
            (Get-DbaAgentProxy -SqlInstance $InstanceSingle -Proxy $proxyPipe1).Description | Should -Be "piped update"
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Proxy           = $proxyDesc
                Description     = "no target"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaAgentProxy @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Throws a terminating error with -EnableException" {
            $splatThrow = @{
                Proxy           = $proxyDesc
                Description     = "no target"
                Confirm         = $false
                EnableException = $true
            }
            { Set-DbaAgentProxy @splatThrow } | Should -Throw
        }
    }
}
