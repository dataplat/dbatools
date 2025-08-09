#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaRegServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "InputObject",
                "Path",
                "FilePath",
                "CredentialPersistenceType",
                "Group",
                "ExcludeGroup",
                "Overwrite",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $testPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $testPath -ItemType Directory

        # Set variables for the test setup
        $srvName1      = "dbatoolsci-server1"
        $group1        = "dbatoolsci-group1"
        $regSrvName1   = "dbatoolsci-server12"
        $regSrvDesc1   = "dbatoolsci-server123"

        $srvName2      = "dbatoolsci-server2"
        $group2        = "dbatoolsci-group2"
        $regSrvName2   = "dbatoolsci-server21"
        $regSrvDesc2   = "dbatoolsci-server321"

        $srvName3      = "dbatoolsci-server3"
        $regSrvName3   = "dbatoolsci-server3"
        $regSrvDesc3   = "dbatoolsci-server3desc"

        # Create the test objects
        $newGroup1 = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance2 -Name $group1
        $newServer1 = Add-DbaRegServer -SqlInstance $TestConfig.instance2 -ServerName $srvName1 -Name $regSrvName1 -Description $regSrvDesc1

        $newGroup2 = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance2 -Name $group2
        $newServer2 = Add-DbaRegServer -SqlInstance $TestConfig.instance2 -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2

        $newServer3 = Add-DbaRegServer -SqlInstance $TestConfig.instance2 -ServerName $srvName3 -Name $regSrvName3 -Description $regSrvDesc3

        $randomValue = Get-Random
        $newDirectory = "$testPath\subdir-$randomValue"

        # Array to track files for cleanup
        $filesToCleanup = @()

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects
        Get-DbaRegServer -SqlInstance $TestConfig.instance2 | Where-Object Name -Match dbatoolsci | Remove-DbaRegServer -Confirm:$false
        Get-DbaRegServerGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -Match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false

        # Remove all test files
        Remove-Item -Path $filesToCleanup -ErrorAction SilentlyContinue
        Remove-Item -Path $testPath -Recurse -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Export functionality" {
        It "Should create an xml file" {
            $results = $newServer1 | Export-DbaRegServer
            $filesToCleanup += $results.FullName

            $results | Should -BeOfType System.IO.FileInfo
            $results.Extension | Should -Be ".xml"
        }

        It "Should create a specific xml file when using Path" {
            $results = $newGroup2 | Export-DbaRegServer -Path $newDirectory
            $filesToCleanup += $results.FullName

            $results | Should -BeOfType System.IO.FileInfo
            $results.FullName | Should -Match "subdir-$randomValue"
            Get-Content -Path $results -Raw | Should -Match $group2
        }

        It "Creates an importable xml file" {
            $exportResults = $newServer3 | Export-DbaRegServer -Path $newDirectory
            $filesToCleanup += $exportResults.FullName

            # Remove existing servers to test import
            Get-DbaRegServer -SqlInstance $TestConfig.instance2 | Where-Object Name -Match dbatoolsci | Remove-DbaRegServer -Confirm:$false
            Get-DbaRegServerGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -Match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false

            $importResults = Import-DbaRegServer -SqlInstance $TestConfig.instance2 -Path $exportResults

            $newServer3.ServerName | Should -BeIn $importResults.ServerName
            $newServer3.Description | Should -BeIn $importResults.Description

            # Re-create the test objects for remaining tests
            $global:newGroup1 = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance2 -Name $group1
            $global:newServer1 = Add-DbaRegServer -SqlInstance $TestConfig.instance2 -ServerName $srvName1 -Name $regSrvName1 -Description $regSrvDesc1

            $global:newGroup2 = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance2 -Name $group2
            $global:newServer2 = Add-DbaRegServer -SqlInstance $TestConfig.instance2 -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2

            $global:newServer3 = Add-DbaRegServer -SqlInstance $TestConfig.instance2 -ServerName $srvName3 -Name $regSrvName3 -Description $regSrvDesc3
        }
    }

    Context "FilePath parameter" {
        It "Create an xml file using FilePath" {
            $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$randomValue.xml"
            $results = Export-DbaRegServer -SqlInstance $TestConfig.instance2 -FilePath $outputFileName
            $filesToCleanup += $outputFileName

            $results | Should -BeOfType System.IO.FileInfo
            $results.FullName | Should -Be $outputFileName
        }

        It "Create a regsrvr file using the FilePath alias OutFile" {
            $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$randomValue.regsrvr"
            $results = Export-DbaRegServer -SqlInstance $TestConfig.instance2 -OutFile $outputFileName
            $filesToCleanup += $outputFileName

            $results | Should -BeOfType System.IO.FileInfo
            $results.FullName | Should -Be $outputFileName
        }

        It "Try to create an invalid file using FilePath" {
            $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$randomValue.txt"
            $results = Export-DbaRegServer -SqlInstance $TestConfig.instance2 -FilePath $outputFileName -WarningAction SilentlyContinue
            # TODO: Test for [Export-DbaRegServer] The FilePath specified must end with either .xml or .regsrvr
            $results | Should -BeNullOrEmpty
        }

        It "Create an xml file using the FilePath alias FileName in a directory that does not yet exist" {
            $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$randomValue.xml"
            $results = Export-DbaRegServer -SqlInstance $TestConfig.instance2 -FileName $outputFileName
            $filesToCleanup += $outputFileName

            $results | Should -BeOfType System.IO.FileInfo
            $results.FullName | Should -Be $outputFileName
        }
    }

    Context "Overwrite parameter" {
        It "Ensure the Overwrite param is working" {
            $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$randomValue.xml"
            $results = Export-DbaRegServer -SqlInstance $TestConfig.instance2 -FilePath $outputFileName
            $filesToCleanup += $outputFileName

            $results | Should -BeOfType System.IO.FileInfo
            $results.FullName | Should -Be $outputFileName

            # test without -Overwrite
            $invalidResults = Export-DbaRegServer -SqlInstance $TestConfig.instance2 -FilePath $outputFileName -WarningAction SilentlyContinue
            # TODO: Test for [Export-DbaRegServer] Use the -Overwrite parameter if the file C:\temp\539615200\dbatoolsci-regsrvr-export-539615200.xml should be overwritten.
            $invalidResults | Should -BeNullOrEmpty

            # test with -Overwrite
            $resultsOverwrite = Export-DbaRegServer -SqlInstance $TestConfig.instance2 -FilePath $outputFileName -Overwrite
            $resultsOverwrite | Should -BeOfType System.IO.FileInfo
            $resultsOverwrite.FullName | Should -Be $outputFileName
        }
    }

    Context "Group filtering" {
        It "Test with the Group param" {
            $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$randomValue.xml"
            $results = Export-DbaRegServer -SqlInstance $TestConfig.instance2 -FilePath $outputFileName -Group $group1
            $filesToCleanup += $outputFileName

            $results | Should -BeOfType System.IO.FileInfo
            $results.FullName | Should -Be $outputFileName

            $fileText = Get-Content -Path $results -Raw

            $fileText | Should -Match $group1
            $fileText | Should -Not -Match $group2
        }

        It "Test with the Group param and multiple group names" {
            $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$randomValue.xml"
            $results = @(Export-DbaRegServer -SqlInstance $TestConfig.instance2 -FilePath $outputFileName -Group @($group1, $group2))
            $filesToCleanup += $results.FullName

            $results.Count | Should -BeExactly 2

            $fileText = Get-Content -Path $results[0] -Raw

            $fileText | Should -Match $group1
            $fileText | Should -Not -Match $group2

            $fileText = Get-Content -Path $results[1] -Raw

            $fileText | Should -Not -Match $group1
            $fileText | Should -Match $group2
        }

        It "Test with the ExcludeGroup param" {
            $results = Export-DbaRegServer -SqlInstance $TestConfig.instance2 -ExcludeGroup $group2
            $filesToCleanup += $results.FullName

            $results | Should -BeOfType System.IO.FileInfo

            $fileText = Get-Content -Path $results -Raw

            $fileText | Should -Match $group1
            $fileText | Should -Not -Match $group2
        }
    }
}