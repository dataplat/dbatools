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
    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaKbUpdate -Name KB4057119 -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "Title",
                "NameLevel",
                "SPLevel",
                "KBLevel",
                "CULevel",
                "BuildLevel",
                "SupportedUntil",
                "Architecture",
                "Language",
                "Hotfix",
                "Description",
                "LastModified",
                "Size",
                "Classification",
                "SupportedProducts",
                "MSRCNumber",
                "MSRCSeverity",
                "RebootBehavior",
                "RequestsUserInput",
                "ExclusiveInstall",
                "NetworkRequired",
                "UninstallNotes",
                "UninstallSteps",
                "UpdateId",
                "Supersedes",
                "SupersededBy",
                "Link"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Output with -Simple" {
        BeforeAll {
            $result = Get-DbaKbUpdate -Name KB4577194 -Simple -EnableException
        }

        It "Returns reduced property set" {
            $expectedProps = @(
                "Title",
                "Architecture",
                "Language",
                "Hotfix",
                "UpdateId",
                "Link"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present with -Simple"
            }
        }

        It "Excludes detailed properties when -Simple specified" {
            $excludedProps = @(
                "LastModified",
                "Description",
                "Size",
                "Classification",
                "SupportedProducts",
                "MSRCNumber",
                "MSRCSeverity",
                "RebootBehavior",
                "RequestsUserInput",
                "ExclusiveInstall",
                "NetworkRequired",
                "UninstallNotes",
                "UninstallSteps",
                "SupersededBy",
                "Supersedes"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $excludedProps) {
                $actualProps | Should -Not -Contain $prop -Because "property '$prop' should be excluded with -Simple"
            }
        }
    }

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
}