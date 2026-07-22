#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaLinkedServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaLinkedServer.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "LinkedServer",
                "InputObject",
                "CollationCompatible",
                "CollationName",
                "ConnectTimeout",
                "DataAccess",
                "Distributor",
                "LazySchemaValidation",
                "Publisher",
                "QueryTimeout",
                "Rpc",
                "RpcOut",
                "Subscriber",
                "UseRemoteCollation",
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
        $hostInstance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $remoteInstance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2

        $linkedServer1Name = "dbatoolscli_linkedServer1_$random"
        $linkedServer2Name = "dbatoolscli_linkedServer2_$random"

        $splatLinkedServer1 = @{
            SqlInstance   = $hostInstance
            LinkedServer  = $linkedServer1Name
            ServerProduct = "mssql"
            Provider      = "sqlncli"
            DataSource    = $remoteInstance
        }
        $null = New-DbaLinkedServer @splatLinkedServer1

        $splatLinkedServer2 = @{
            SqlInstance   = $hostInstance
            LinkedServer  = $linkedServer2Name
            ServerProduct = "mssql"
            Provider      = "sqlncli"
            DataSource    = $remoteInstance
        }
        $null = New-DbaLinkedServer @splatLinkedServer2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaLinkedServer -SqlInstance $hostInstance -LinkedServer $linkedServer1Name, $linkedServer2Name -Force -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits the designed ShouldProcess string and changes nothing" {
            # WhatIf text is HOST-DIRECT: *>&1 / 6>&1 capture nothing in-process, so a transcript
            # is the reliable in-Pester capture. The asserted string is verbatim from the signed
            # spec's shouldProcessTargets with its placeholders resolved.
            $before = (Get-DbaLinkedServer -SqlInstance $hostInstance -LinkedServer $linkedServer1Name).Rpc

            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_whatif_$random.txt"
            $splatWhatIf = @{
                SqlInstance  = $hostInstance
                LinkedServer = $linkedServer1Name
                Rpc          = -not $before
                WhatIf       = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Set-DbaLinkedServer @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedAction = "Altering linked server $linkedServer1Name"
                $expectedTarget = $hostInstance.DomainInstanceName
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAction`" on target `"$expectedTarget`""))
            } finally {
                # Stop-Transcript writes to the error stream even under -ErrorAction
                # SilentlyContinue when the host is no longer transcribing, and Pester counts that
                # as a failure - swallow it in a catch instead.
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and the side effect did NOT happen.
            $after = (Get-DbaLinkedServer -SqlInstance $hostInstance -LinkedServer $linkedServer1Name).Rpc
            $after | Should -Be $before
        }
    }

    Context "Command behavior" {
        It "Alters an option via -SqlInstance and re-emits the decorated object" {
            $splatSet = @{
                SqlInstance     = $hostInstance
                LinkedServer    = $linkedServer2Name
                Rpc             = $true
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaLinkedServer @splatSet
            $result.Rpc | Should -BeTrue
            # Decoration parity with Get-DbaLinkedServer so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.RemoteServer | Should -Be $result.DataSource
        }

        It "Turns an option off when explicitly passed -Rpc:`$false (switch tri-state)" {
            $splatOff = @{
                SqlInstance     = $hostInstance
                LinkedServer    = $linkedServer2Name
                Rpc             = $false
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaLinkedServer @splatOff
            $result.Rpc | Should -BeFalse
        }

        It "Leaves an unbound option untouched" {
            # THE regression this command is most likely to have: applying an option the caller did
            # not pass would silently overwrite it. Set RpcOut to a known state, then change only
            # Rpc and assert RpcOut is unchanged.
            $null = Set-DbaLinkedServer -SqlInstance $hostInstance -LinkedServer $linkedServer1Name -RpcOut:$true -EnableException -Confirm:$false
            $null = Set-DbaLinkedServer -SqlInstance $hostInstance -LinkedServer $linkedServer1Name -Rpc:$true -EnableException -Confirm:$false
            (Get-DbaLinkedServer -SqlInstance $hostInstance -LinkedServer $linkedServer1Name).RpcOut | Should -BeTrue
        }

        It "Processes multiple piped linked servers and resolves each record's own parent (N in, N out)" {
            # Mandatory multi-record piped leg: each piped record resolves its OWN linked server,
            # so the two results report the two DISTINCT names, not the first one twice.
            $splatGetPair = @{
                SqlInstance  = $hostInstance
                LinkedServer = $linkedServer1Name, $linkedServer2Name
            }
            $results = Get-DbaLinkedServer @splatGetPair | Set-DbaLinkedServer -DataAccess:$true -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            ($results.Name | Sort-Object -Unique) | Should -Be @($linkedServer1Name, $linkedServer2Name | Sort-Object)
            $results.DataAccess | Should -Not -Contain $false
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Rpc             = $true
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaLinkedServer @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues on an unknown linked server without -EnableException" {
            $splatWarn = @{
                SqlInstance     = $hostInstance
                LinkedServer    = "dbatoolscli_invalidServer_$random", $linkedServer2Name
                Rpc             = $true
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            $results = Set-DbaLinkedServer @splatWarn
            $warn | Should -Not -BeNullOrEmpty
            ($results | Measure-Object).Count | Should -Be 1
        }

        It "Throws a terminating error with -EnableException" {
            $splatThrow = @{
                SqlInstance     = $hostInstance
                LinkedServer    = "dbatoolscli_invalidServer_$random"
                Rpc             = $true
                Confirm         = $false
                EnableException = $true
            }
            { Set-DbaLinkedServer @splatThrow } | Should -Throw
        }
    }
}
