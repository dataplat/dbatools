#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDirectory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Path",
                "SqlCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # save the prior EnableException default and restore it in finally, so a setup failure never
        # leaves the forced value enabled for later describes.
        $priorEnableException = $PSDefaultParameterValues["*-Dba*:EnableException"]
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        try {
            # New-DbaDirectory creates the folder on the SQL Server machine via xp_create_subdir,
            # using the SQL service account. The instance backup directory is writable by that
            # account, so new subfolders under it are a safe target. Test-DbaPath is the command's
            # own existence check.
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $baseDir = $server.BackupDirectory
            $random = Get-Random
            $happyDir = "$baseDir\dbatoolsci_nd_happy_$random"
            $existDir = "$baseDir\dbatoolsci_nd_exist_$random"
            $whatIfDir = "$baseDir\dbatoolsci_nd_whatif_$random"

            # pre-create the "already exists" target through the command itself so the exists-guard
            # test has a real server-side directory regardless of where the instance lives.
            $splatPre = @{
                SqlInstance = $TestConfig.InstanceSingle
                Path        = $existDir
                Confirm     = $false
            }
            $null = New-DbaDirectory @splatPre
        } finally {
            if ($null -ne $priorEnableException) {
                $PSDefaultParameterValues["*-Dba*:EnableException"] = $priorEnableException
            } else {
                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            }
        }
    }

    AfterAll {
        # These folders live on the SQL Server host. When the instance is local (as on the lab gate)
        # Remove-Item cleans them; the Test-Path guard means only paths actually on the test runner
        # are touched. There is no Remove-DbaDirectory counterpart, so for a genuinely remote instance
        # the empty test folders are a known, harmless residue on that host.
        foreach ($dir in $happyDir, $existDir, $whatIfDir) {
            if ($dir -and (Test-Path -Path $dir)) {
                Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Creating a directory" {
        It "Creates a new directory and reports Created true" {
            $splatNew = @{
                SqlInstance = $TestConfig.InstanceSingle
                Path        = $happyDir
                Confirm     = $false
            }
            $result = @(New-DbaDirectory @splatNew)
            $result.Count | Should -Be 1
            $created = $result[0]
            $created | Should -BeOfType System.Management.Automation.PSCustomObject
            $created.Path | Should -Be $happyDir
            $created.Created | Should -BeTrue
            # Server column carries the targeted instance
            "$($created.Server)" | Should -Be "$($TestConfig.InstanceSingle)"
            foreach ($prop in "Server", "Path", "Created") {
                $created.PSObject.Properties.Name | Should -Contain $prop
            }
            # the directory really exists on the instance now
            Test-DbaPath -SqlInstance $TestConfig.InstanceSingle -Path $happyDir | Should -BeTrue
        }

        It "Warns and emits nothing when the path already exists" {
            $splatExists = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Path            = $existDir
                Confirm         = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = New-DbaDirectory @splatExists
            $result | Should -BeNullOrEmpty
            $warn.Count | Should -Be 1
            $warn[0] | Should -BeLike "*$existDir already exists*"
            # the guard must not delete the existing directory - it still exists afterward
            Test-DbaPath -SqlInstance $TestConfig.InstanceSingle -Path $existDir | Should -BeTrue
        }

        It "Creates nothing under -WhatIf" {
            $splatWhatIf = @{
                SqlInstance = $TestConfig.InstanceSingle
                Path        = $whatIfDir
                WhatIf      = $true
            }
            $result = New-DbaDirectory @splatWhatIf
            $result | Should -BeNullOrEmpty
            # ShouldProcess was declined, so the directory was never created
            Test-DbaPath -SqlInstance $TestConfig.InstanceSingle -Path $whatIfDir | Should -BeFalse
        }
    }
}