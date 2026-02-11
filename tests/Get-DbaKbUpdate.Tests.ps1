#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaKbUpdate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Name",
                "Simple",
                "Language",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    It "successfully connects and parses link and title" {
        $results = Get-DbaKbUpdate -Name KB4057119
        $results.Link -match "download.windowsupdate.com"
        $results.Title -match "Cumulative Update"
        $results.KBLevel | Should -Be 4057119
    }

    It "test with the -Simple param" {
        $results = Get-DbaKbUpdate -Name KB4577194 -Simple
        $results.Link -match "download.windowsupdate.com"
        $results.Title -match "Cumulative Update"
        $results.KBLevel | Should -Be 4577194
    }

    # see https://github.com/dataplat/dbatools/issues/6745
    It "Calling script uses a variable named filter" {
        $filter = "SQLServer*-KB-*x64*.exe"

        $results = Get-DbaKbUpdate -Name KB4564903
        $results.KBLevel | Should -Be 4564903
        $results.Link -match "download.windowsupdate.com"
        $results.Title -match "Cumulative Update"
    }

    It "Call with multiple KBs" {
        $results = Get-DbaKbUpdate -Name KB4057119, KB4577194, KB4564903

        # basic retry logic in case the first download didn't get all of the files
        if ($null -eq $results -or $results.Count -ne 3) {
            Write-Message -Level Warning -Message "Retrying..."
            Start-Sleep -s 30
            $results = Get-DbaKbUpdate -Name KB4057119, KB4577194, KB4564903
        }

        $results.KBLevel | Should -Contain 4057119
        $results.KBLevel | Should -Contain 4577194
        $results.KBLevel | Should -Contain 4564903
    }

    It "Call without specific language" {
        $results = Get-DbaKbUpdate -Name KB5003279
        $results.KBLevel | Should -Be 5003279
        $results.Classification -match "Service Packs"
        $results.Link -match "-enu_"
    }

    It "Call with specific language" {
        $results = Get-DbaKbUpdate -Name KB5003279 -Language ja
        $results.KBLevel | Should -Be 5003279
        $results.Classification -match "Service Packs"
        $results.Link -match "-jpn_"
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaKbUpdate -Name KB4057119
        }

        It "Returns output of the expected type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            # Base properties that should always be present
            $expectedDefaults = @(
                "Title",
                "Architecture",
                "Language",
                "Hotfix",
                "UpdateId",
                "Link"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has build-level properties when build info is available" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            if (-not $result[0].NameLevel) { Set-ItResult -Skipped -Because "build info not available for this KB" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $buildProps = @(
                "NameLevel",
                "SPLevel",
                "KBLevel",
                "CULevel",
                "BuildLevel",
                "SupportedUntil"
            )
            foreach ($prop in $buildProps) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set when build info is available"
            }
        }
    }
}