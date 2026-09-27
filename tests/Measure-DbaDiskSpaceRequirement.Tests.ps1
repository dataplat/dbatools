#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Measure-DbaDiskSpaceRequirement",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Database",
                "SourceSqlCredential",
                "Destination",
                "DestinationDatabase",
                "DestinationSqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Should Measure Disk Space Required" {
        BeforeAll {
            $server1 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
            $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2

            $splatMeasure = @{
                Source              = $TestConfig.InstanceCopy1
                Destination         = $TestConfig.InstanceCopy2
                Database            = "master"
                DestinationDatabase = "Dbatoolsci_DestinationDB"
            }
            $results = Measure-DbaDiskSpaceRequirement @splatMeasure
        }

        It "Should have information" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be sourced from Master" {
            $results[0].SourceDatabase | Should -Be $splatMeasure.Database
        }

        It "Should be sourced from the instance $($TestConfig.InstanceCopy1)" {
            $results[0].SourceSqlInstance | Should -Be $server1.SqlInstance
        }

        It "Should be destined for Dbatoolsci_DestinationDB" {
            $results[0].DestinationDatabase | Should -Be $splatMeasure.DestinationDatabase
        }

        It "Should be destined for the instance $($TestConfig.InstanceCopy2)" {
            $results[0].DestinationSqlInstance | Should -Be $server2.SqlInstance
        }

        It "Should have files on source" {
            $results[0].FileLocation | Should -Be "Only on Source"
        }
    }

    Context "When the mount points cannot be read" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $dbName = "dbatoolsci_measure_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Name $dbName
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Name $dbName
            $extraFileName = "dbatoolsci_extra"
            $null = Add-DbaDbFile -SqlInstance $TestConfig.InstanceCopy2 -Database $dbName -FileGroup PRIMARY -FileName $extraFileName
            $extraFile = (Get-DbaDbFile -SqlInstance $TestConfig.InstanceCopy2 -Database $dbName | Where-Object LogicalName -eq $extraFileName).PhysicalName

            # A credential that cannot query WMI on the destination computer: remotely it is refused, locally
            # WMI does not take credentials at all. Either way reading the mount points fails.
            $splatPassword = @{
                String      = "dbatools.IO$(Get-Random)!"
                AsPlainText = $true
                Force       = $true
            }
            $badCredential = New-Object System.Management.Automation.PSCredential ("dbatoolsci_nouser", (ConvertTo-SecureString @splatPassword))

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $dbName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        # The helpers called Stop-Function -Continue, which has no loop in the helper: the continue escaped into
        # the loop over the files and skipped the row, and the code that cached and returned "?" never ran.
        It "Returns every file, with ? as mount point, when the destination database does not exist" {
            $splatMeasure = @{
                Source              = $TestConfig.InstanceCopy1
                Database            = $dbName
                Destination         = $TestConfig.InstanceCopy2
                DestinationDatabase = "dbatoolsci_notthere_$(Get-Random)"
                Credential          = $badCredential
                WarningAction       = "SilentlyContinue"
            }
            $results = @(Measure-DbaDiskSpaceRequirement @splatMeasure)
            $results | Should -HaveCount 2
            $results.MountPoint | Should -Be @("?", "?")
            @($WarnVar -like "*Can't connect to*") | Should -HaveCount 1
        }

        It "Returns every file, with ? as mount point, when the destination database exists" {
            $results = @(Measure-DbaDiskSpaceRequirement -Source $TestConfig.InstanceCopy1 -Database $dbName -Destination $TestConfig.InstanceCopy2 -Credential $badCredential -WarningAction SilentlyContinue)
            $results | Should -HaveCount 3
            $results.MountPoint | Should -Be @("?", "?", "?")
        }

        It "Names the file of a row that exists only on the destination" {
            # The row read the file name from the variable of an earlier loop instead of its own file.
            $results = @(Measure-DbaDiskSpaceRequirement -Source $TestConfig.InstanceCopy1 -Database $dbName -Destination $TestConfig.InstanceCopy2 -Credential $badCredential -WarningAction SilentlyContinue)
            $destinationOnly = $results | Where-Object FileLocation -eq "Only on Destination"
            $destinationOnly.DestinationLogicalName | Should -Be $extraFileName
            $destinationOnly.DestinationFileName | Should -Be $extraFile
        }

        It "Warns when the source database does not exist" {
            # -Database is mandatory, so the old check with Test-Bound never fired.
            $results = Measure-DbaDiskSpaceRequirement -Source $TestConfig.InstanceCopy1 -Database "dbatoolsci_nodb_$(Get-Random)" -Destination $TestConfig.InstanceCopy2 -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            $WarnVar | Should -BeLike "*MUST exist on Source Instance*"
        }
    }
}