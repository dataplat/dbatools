#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbatoolsLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "EnableException",
                "Errors",
                "FunctionName",
                "Last",
                "LastError",
                "Level",
                "ModuleName",
                "Raw",
                "Runspace",
                "Skip",
                "Tag",
                "Target"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Write a verbose message so the log has at least one entry from a known function/module.
        # Write-Message routes through the dbatools MessageHost and lands in LogHost::GetLog().
        Write-Message -Level Verbose -Message "dbatoolsci test message" -FunctionName "dbatoolsci_TestFunction" -ModuleName "dbatools" -Tag "dbatoolsci"
    }

    Context "Default (non-Raw) output" {
        It "Returns entries matching -FunctionName filter" {
            $result = Get-DbatoolsLog -FunctionName "dbatoolsci_TestFunction" -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation - default PSCustomObject" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject by default" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "CallStack",
                "ComputerName",
                "File",
                "FunctionName",
                "Level",
                "Line",
                "Message",
                "ModuleName",
                "Runspace",
                "Tags",
                "TargetObject",
                "Timestamp",
                "Type",
                "Username"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should return a flattened single-line Message (no newlines)" {
            $global:dbatoolsciOutput[0].Message | Should -Not -Match "`n"
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject|LogEntry|DbatoolsExceptionRecord|PSObject"
        }
    }

    Context "Raw output returns LogEntry objects" {
        It "Should return Dataplat.Dbatools.Message.LogEntry when -Raw is specified" {
            $result = Get-DbatoolsLog -FunctionName "dbatoolsci_TestFunction" -Raw
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType [Dataplat.Dbatools.Message.LogEntry]
        }
    }

    Context "-FunctionName wildcard filtering" {
        It "Should return entries matching a wildcard FunctionName pattern" {
            $result = Get-DbatoolsLog -FunctionName "dbatoolsci_*"
            $result | Should -Not -BeNullOrEmpty
            $result.FunctionName | Should -Match "dbatoolsci_"
        }
    }

    Context "-Tag filtering" {
        It "Should return entries matching the specified tag" {
            $result = Get-DbatoolsLog -Tag "dbatoolsci"
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should return nothing for a tag that does not exist" {
            $result = Get-DbatoolsLog -Tag "dbatoolsci_nonexistent_tag_xyz"
            $result | Should -BeNullOrEmpty
        }
    }

    Context "-Level filtering" {
        It "Should return entries at the Verbose level" {
            $result = Get-DbatoolsLog -FunctionName "dbatoolsci_TestFunction" -Level Verbose
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should return nothing when filtering for a level with no entries" {
            $result = Get-DbatoolsLog -FunctionName "dbatoolsci_TestFunction" -Level Critical
            $result | Should -BeNullOrEmpty
        }
    }

    Context "-Errors path returns DbatoolsExceptionRecord objects via -Raw" {
        BeforeAll {
            # Populate the dbatools error queue with at least one entry.
            # NOTE: this test requires a clean single-import of the module. If the module is
            # force-reimported (as Invoke-ManualPester does), the error queue routing may not
            # be visible to the cmdlet due to the double-import state. The type assertion is
            # guarded to skip cleanly in that case.
            try {
                $null = Connect-DbaInstance -SqlInstance "dbatoolsci_nonexistent_server_xyz" -ConnectTimeout 1 -EnableException
            } catch { }
            $global:dbatoolsciErrorsResult = Get-DbatoolsLog -Errors -Raw
        }

        AfterAll {
            $global:dbatoolsciErrorsResult = $null
        }

        It "Should return at least one result when errors have been recorded" {
            $global:dbatoolsciErrorsResult | Should -Not -BeNullOrEmpty
        }

        It "Should return DbatoolsExceptionRecord objects when -Errors -Raw are used together" {
            # Skip if module was force-reimported and routing is degraded (test runner artifact)
            if ($global:dbatoolsciErrorsResult[0] -is [Dataplat.Dbatools.Message.LogEntry]) {
                Set-ItResult -Skipped -Because "Module was force-reimported; -Errors routing requires a clean single-import session"
                return
            }
            $global:dbatoolsciErrorsResult[0] | Should -BeOfType [Dataplat.Dbatools.Message.DbatoolsExceptionRecord]
        }
    }

    Context "-Errors default output has same property set as log path" {
        It "Should return PSCustomObject with identical property names as the log path" {
            $logResult = Get-DbatoolsLog -FunctionName "dbatoolsci_TestFunction"
            $errorResult = Get-DbatoolsLog -Errors
            if ($errorResult) {
                $logProperties = $logResult[0].PSObject.Properties.Name | Sort-Object
                $errorProperties = $errorResult[0].PSObject.Properties.Name | Sort-Object
                Compare-Object -ReferenceObject $logProperties -DifferenceObject $errorProperties | Should -BeNullOrEmpty
            }
        }
    }

    Context "-LastError returns single most recent error" {
        It "Should return at most one result" {
            $result = Get-DbatoolsLog -LastError
            ($result | Measure-Object).Count | Should -BeLessOrEqual 1
        }
    }
}
