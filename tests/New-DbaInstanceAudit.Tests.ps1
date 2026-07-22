#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaInstanceAudit",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/New-DbaInstanceAudit.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Audit",
                "InputObject",
                "DestinationType",
                "FilePath",
                "Filter",
                "MaximumFileSize",
                "MaximumFileSizeUnit",
                "MaximumFiles",
                "MaximumRolloverFiles",
                "OnFailure",
                "QueueDelay",
                "ReserveDiskSpace",
                "Enable",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Exposes Enable and ReserveDiskSpace as switches, not [bool] (dbatools house style)" {
            foreach ($switchName in "Enable", "ReserveDiskSpace") {
                (Get-Command $CommandName).Parameters[$switchName].ParameterType.Name | Should -Be "SwitchParameter"
            }
        }

        It "Types MaximumRolloverFiles as Int64 and MaximumFiles as Int32 (the spec typing trap)" {
            (Get-Command $CommandName).Parameters["MaximumRolloverFiles"].ParameterType.Name | Should -Be "Int64"
            (Get-Command $CommandName).Parameters["MaximumFiles"].ParameterType.Name | Should -Be "Int32"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # Audit FILEPATH must be a directory that exists on the SQL host and the service account can write.
        $auditPath = (Get-DbaDefaultPath -SqlInstance $InstanceSingle).Data

        $audit1Name = "dbatoolsci_audit1_$random"
        $audit2Name = "dbatoolsci_audit2_$random"
        $auditEnableName = "dbatoolsci_auditen_$random"
        $auditPipeName = "dbatoolsci_auditpipe_$random"
        $auditWhatIfName = "dbatoolsci_auditwi_$random"

        $allAuditNames = @($audit1Name, $audit2Name, $auditEnableName, $auditPipeName, $auditWhatIfName)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # There is no Remove-DbaInstanceAudit yet (pending row), so tear down through SMO: disable
        # before dropping because an enabled audit holds its file.
        $cleanupServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $cleanupServer.Audits.Refresh()
        foreach ($name in $allAuditNames) {
            $existing = $cleanupServer.Audits[$name]
            if ($existing) {
                if ($existing.Enabled) { $existing.Disable() }
                $existing.Drop()
            }
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits the designed ShouldProcess string and creates nothing" {
            # -WhatIf must show the operation AND leave the server untouched. WhatIf text is
            # HOST-DIRECT: *>&1 / 6>&1 capture nothing in-process, so a transcript is the reliable
            # in-Pester capture.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_whatif_$random.txt"
            $splatWhatIf = @{
                SqlInstance     = $InstanceSingle
                Audit           = $auditWhatIfName
                DestinationType = "File"
                FilePath        = $auditPath
                WhatIf          = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                New-DbaInstanceAudit @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $InstanceSingle.DomainInstanceName
                $expectedAction = "Creating server audit $auditWhatIfName"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAction`" on target `"$expectedTarget`""))
            } finally {
                # Stop-Transcript writes to the error stream when the host is no longer transcribing,
                # and Pester counts that as a failure - swallow it in a catch instead.
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and the side effect did NOT happen.
            Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditWhatIfName | Should -BeNullOrEmpty
        }
    }

    Context "Command behavior" {
        It "Creates a single audit via -SqlInstance, disabled by default, decorated like Get-DbaInstanceAudit" {
            $splatCreate = @{
                SqlInstance     = $InstanceSingle
                Audit           = $audit1Name
                DestinationType = "File"
                FilePath        = $auditPath
                EnableException = $true
                Confirm         = $false
            }
            $result = New-DbaInstanceAudit @splatCreate
            $result.Name | Should -Be $audit1Name
            # Audits are created disabled by default (matching the server) - -Enable was not bound.
            $result.IsEnabled | Should -Be $false
            # Decoration parity with Get-DbaInstanceAudit so Get -> New -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.FullName | Should -Not -BeNullOrEmpty

            $readBack = Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $audit1Name
            $readBack.Name | Should -Be $audit1Name
            $readBack.DestinationType | Should -Be "File"
        }

        It "Creates an audit already enabled with -Enable (Enable is a method call, not a property set)" {
            $splatEnable = @{
                SqlInstance     = $InstanceSingle
                Audit           = $auditEnableName
                DestinationType = "File"
                FilePath        = $auditPath
                Enable          = $true
                EnableException = $true
                Confirm         = $false
            }
            $result = New-DbaInstanceAudit @splatEnable
            $result.IsEnabled | Should -Be $true
            (Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditEnableName).Enabled | Should -Be $true
        }

        It "Creates multiple audits in one call (N names in, N audits out) and each lands on the server" {
            # Mandatory multi-record leg: the per-name create loop. Both audits must come back and
            # both must actually exist server-side - read back independently.
            $splatMulti = @{
                SqlInstance     = $InstanceSingle
                Audit           = $audit2Name, $auditPipeName
                DestinationType = "File"
                FilePath        = $auditPath
                EnableException = $true
                Confirm         = $false
            }
            $results = New-DbaInstanceAudit @splatMulti
            ($results | Measure-Object).Count | Should -Be 2
            ($results.Name | Sort-Object -Unique) | Should -Be @($audit2Name, $auditPipeName | Sort-Object)

            Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $audit2Name | Should -Not -BeNullOrEmpty
            Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditPipeName | Should -Not -BeNullOrEmpty
        }

        It "Accepts an SMO Server piped in via -InputObject" {
            # The InputObject feeder is Smo.Server[] (not the getCounterpart's Audit type) - you
            # cannot pipe an existing audit into a command that creates audits.
            $pipeName = "dbatoolsci_auditsrv_$random"
            $script:allAuditNames += $pipeName
            $result = $InstanceSingle | New-DbaInstanceAudit -Audit $pipeName -DestinationType File -FilePath $auditPath -Confirm:$false -EnableException
            $result.Name | Should -Be $pipeName
            Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $pipeName | Should -Not -BeNullOrEmpty
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Audit           = "dbatoolsci_none_$random"
                DestinationType = "File"
                FilePath        = $auditPath
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = New-DbaInstanceAudit @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Requires -DestinationType" {
            $splatNoDest = @{
                SqlInstance     = $InstanceSingle
                Audit           = "dbatoolsci_nodest_$random"
                FilePath        = $auditPath
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnDest"
            }
            $results = New-DbaInstanceAudit @splatNoDest
            $warnDest | Should -BeLike "*You must specify -DestinationType*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues when FilePath is missing for a File destination without -EnableException" {
            $splatNoPath = @{
                SqlInstance     = $InstanceSingle
                Audit           = "dbatoolsci_nopath_$random"
                DestinationType = "File"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnPath"
            }
            $results = New-DbaInstanceAudit @splatNoPath
            $warnPath | Should -BeLike "*You must specify -FilePath*"
            $results | Should -BeNullOrEmpty
        }

        It "Throws a terminating error when FilePath is missing with -EnableException" {
            $splatThrow = @{
                SqlInstance     = $InstanceSingle
                Audit           = "dbatoolsci_throw_$random"
                DestinationType = "File"
                Confirm         = $false
                EnableException = $true
            }
            { New-DbaInstanceAudit @splatThrow } | Should -Throw
        }
    }
}
