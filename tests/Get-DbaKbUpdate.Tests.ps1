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
        $results = Get-DbaKbUpdate -Name KB4057119 -OutVariable "global:dbatoolsciOutput"
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
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
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
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "Title",
                "Description",
                "Architecture",
                "NameLevel",
                "SPLevel",
                "KBLevel",
                "CULevel",
                "BuildLevel",
                "SupportedUntil",
                "Language",
                "Classification",
                "SupportedProducts",
                "MSRCNumber",
                "MSRCSeverity",
                "Hotfix",
                "Size",
                "UpdateId",
                "RebootBehavior",
                "RequestsUserInput",
                "ExclusiveInstall",
                "NetworkRequired",
                "UninstallNotes",
                "UninstallSteps",
                "SupersededBy",
                "Supersedes",
                "LastModified",
                "Link"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}