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

    Context "Native local registered-server exports" {
        BeforeAll {
            $nativeStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore
            $nativeRoot = $nativeStore.DatabaseEngineServerGroup
            $parentA = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($nativeRoot, "ParentA")
            $parentB = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($nativeRoot, "ParentB")
            $sharedGroupA = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($parentA, "Shared")
            $sharedGroupB = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($parentB, "Shared")
            $localServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($sharedGroupA, "LocalAlias")
            $localServer.ServerName = "localhost\SQLEXPRESS"
            $centralServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($sharedGroupA, "CentralAlias")
            $centralServer.ServerName = "application-sql"
            $centralServer | Add-Member -Name SqlInstance -MemberType NoteProperty -Value "cms\prod" -Force
            $script:regServerExportFiles = @()
        }

        AfterAll {
            $script:regServerExportFiles | Remove-Item -ErrorAction SilentlyContinue
        }

        It "exports a local RegisteredServer with a generated name and preserves an explicit FilePath" {
            $generatedFile = $localServer | Export-DbaRegServer -Path $TestDrive -EnableException
            $explicitPath = Join-Path $TestDrive "explicit-local.xml"
            $explicitFile = $localServer | Export-DbaRegServer -FilePath $explicitPath -EnableException
            $script:regServerExportFiles += $generatedFile, $explicitFile

            $generatedFile.Name | Should -BeLike "localhost`$SQLEXPRESS-regserver-LocalAlias-*.xml"
            $explicitFile.FullName | Should -Be $explicitPath
        }

        It "uses the existing SqlInstance prefix for a central registered server" {
            $centralFile = $centralServer | Export-DbaRegServer -Path $TestDrive -EnableException
            $script:regServerExportFiles += $centralFile

            $centralFile.Name | Should -BeLike "cms`$prod-regserver-CentralAlias-*.xml"
        }

        It "exports same-named local groups to collision-free generated and explicit paths" {
            $generatedFiles = Export-DbaRegServer -InputObject @($sharedGroupA, $sharedGroupB) -Path $TestDrive -EnableException
            $explicitBase = Join-Path $TestDrive "groups.xml"
            $explicitFiles = Export-DbaRegServer -InputObject @($sharedGroupA, $sharedGroupB) -FilePath $explicitBase -EnableException
            $script:regServerExportFiles += $generatedFiles
            $script:regServerExportFiles += $explicitFiles
            $script:regServerExportFiles += Get-Item -LiteralPath $explicitBase

            $generatedFiles | Should -HaveCount 2
            $generatedFiles.FullName | Select-Object -Unique | Should -HaveCount 2
            $explicitFiles | Should -HaveCount 2
            $explicitFiles.FullName | Select-Object -Unique | Should -HaveCount 2
            $generatedFiles.Name -join "," | Should -BeLike "*ParentA`$Shared*"
            $generatedFiles.Name -join "," | Should -BeLike "*ParentB`$Shared*"
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
