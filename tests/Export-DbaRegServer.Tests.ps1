#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaRegServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "InputObject",
                "Path",
                "FilePath",
                "CredentialPersistenceType",
                "EnableException",
                "Group",
                "ExcludeGroup",
                "Overwrite"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeEach {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $srvName = "dbatoolsci-server1"
        $group = "dbatoolsci-group1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"

        $newGroup = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $group
        $newServer = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName -Name $regSrvName -Description $regSrvDesc

        $srvName2 = "dbatoolsci-server2"
        $group2 = "dbatoolsci-group2"
        $regSrvName2 = "dbatoolsci-server21"
        $regSrvDesc2 = "dbatoolsci-server321"

        $newGroup2 = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $group2
        $newServer2 = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2

        $regSrvName3 = "dbatoolsci-server3"
        $srvName3 = "dbatoolsci-server3"
        $regSrvDesc3 = "dbatoolsci-server3desc"

        $newServer3 = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName3 -Name $regSrvName3 -Description $regSrvDesc3

        $random = Get-Random
        $newDirectory = "$($TestConfig.Temp)\$CommandName-$random"
        $null = New-Item -Path $newDirectory -ItemType Directory -Force

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterEach {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -Match dbatoolsci | Remove-DbaRegServer
        Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -Match dbatoolsci | Remove-DbaRegServerGroup
        $results, $results2, $results3 | Remove-Item -ErrorAction SilentlyContinue

        Remove-Item $newDirectory -ErrorAction SilentlyContinue -Recurse -Force

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "should create an xml file" {
        $results = $newServer | Export-DbaRegServer
        $results -is [System.IO.FileInfo] | Should -Be $true
        $results.Extension -eq ".xml" | Should -Be $true
    }

    It "should create a specific xml file when using Path" {
        $results2 = $newGroup2 | Export-DbaRegServer -Path $newDirectory
        $results2 -is [System.IO.FileInfo] | Should -Be $true
        $results2.FullName | Should -Match ([regex]::escape($newDirectory))
        Get-Content -Path $results2 -Raw | Should -Match $group2
    }

    It "creates an importable xml file" {
        $results3 = $newServer3 | Export-DbaRegServer -Path $newDirectory
        Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -Match dbatoolsci | Remove-DbaRegServer
        Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -Match dbatoolsci | Remove-DbaRegServerGroup
        $results4 = Import-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -Path $results3
        $newServer3.ServerName | Should -BeIn $results4.ServerName
        $newServer3.Description | Should -BeIn $results4.Description
    }

    It "Create an xml file using FilePath" {
        $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$random.xml"
        $results = Export-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -FilePath $outputFileName
        $results -is [System.IO.FileInfo] | Should -Be $true
        $results.FullName | Should -Be $outputFileName
    }

    It "Create a regsrvr file using the FilePath alias OutFile" {
        $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$random.regsrvr"
        $results = Export-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -OutFile $outputFileName
        $results -is [System.IO.FileInfo] | Should -Be $true
        $results.FullName | Should -Be $outputFileName
    }

    It "Try to create an invalid file using FilePath" {
        $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$random.txt"
        $results = Export-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -FilePath $outputFileName -WarningAction SilentlyContinue
        # TODO: Test for [Export-DbaRegServer] The FilePath specified must end with either .xml or .regsrvr
        $results.length | Should -Be 0
    }

    It "Create an xml file using the FilePath alias FileName in a directory that does not yet exist" {
        $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$random.xml"
        $results = Export-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -FileName $outputFileName
        $results -is [System.IO.FileInfo] | Should -Be $true
        $results.FullName | Should -Be $outputFileName
    }

    It "Ensure the Overwrite param is working" {
        $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$random.xml"
        $results = Export-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -FilePath $outputFileName
        $results -is [System.IO.FileInfo] | Should -Be $true
        $results.FullName | Should -Be $outputFileName

        # test without -Overwrite
        $invalidResults = Export-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -FilePath $outputFileName -WarningAction SilentlyContinue
        # TODO: Test for [Export-DbaRegServer] Use the -Overwrite parameter if the file C:\temp\539615200\dbatoolsci-regsrvr-export-539615200.xml should be overwritten.
        $invalidResults.length | Should -Be 0

        # test with -Overwrite
        $resultsOverwrite = Export-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -FilePath $outputFileName -Overwrite
        $resultsOverwrite -is [System.IO.FileInfo] | Should -Be $true
        $resultsOverwrite.FullName | Should -Be $outputFileName
    }

    It "Test with the Group param" {
        $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$random.xml"
        $results = Export-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -FilePath $outputFileName -Group $group
        $results -is [System.IO.FileInfo] | Should -Be $true
        $results.FullName | Should -Be $outputFileName

        $fileText = Get-Content -Path $results -Raw

        $fileText | Should -Match $group
        $fileText | Should -Not -Match $group2
    }

    It "Test with the Group param and multiple group names" {
        $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$random.xml"
        $results = Export-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -FilePath $outputFileName -Group @($group, $group2)
        $results.length | Should -Be 2

        $fileText = Get-Content -Path $results[0] -Raw

        $fileText | Should -Match $group
        $fileText | Should -Not -Match $group2

        $fileText = Get-Content -Path $results[1] -Raw

        $fileText | Should -Not -Match $group
        $fileText | Should -Match $group2
    }

    It "Test with the ExcludeGroup param" {
        $results = Export-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ExcludeGroup $group2
        $results -is [System.IO.FileInfo] | Should -Be $true

        $fileText = Get-Content -Path $results -Raw

        $fileText | Should -Match $group
        $fileText | Should -Not -Match $group2
    }
}

Describe "$CommandName - Output validation" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $outputRandom = Get-Random
        $outputSrvName = "dbatoolsci-output-server-$outputRandom"
        $outputRegSrvName = "dbatoolsci-output-regsrv-$outputRandom"
        $outputNewDirectory = "$($TestConfig.Temp)\$CommandName-output-$outputRandom"
        $null = New-Item -Path $outputNewDirectory -ItemType Directory -Force

        $outputServer = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $outputSrvName -Name $outputRegSrvName -Description "Output validation test"
        $outputResult = $outputServer | Export-DbaRegServer -Path $outputNewDirectory

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # Clean up using direct SQL to avoid broken Remove-DbaRegServer
        try {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $server.Query("DELETE FROM msdb.dbo.sysmanagement_shared_registered_servers_internal WHERE name LIKE 'dbatoolsci-output-%'")
        } catch {
            # Ignore cleanup errors
        }
        Remove-Item -Path $outputNewDirectory -Recurse -ErrorAction SilentlyContinue
    }

    It "Returns output of the documented type" {
        if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
        $outputResult | Should -BeOfType [System.IO.FileInfo]
    }

    It "Returns an XML file" {
        if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
        $outputResult.Extension | Should -Be ".xml"
    }
}