$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        It "Should only contain our specific parameters" {
            [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
            [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'InputObject', 'Path', 'FilePath', 'CredentialPersistenceType', 'EnableException', 'Group', 'ExcludeGroup', 'Overwrite'
            $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeEach {
        $srvName = "dbatoolsci-server1"
        $group = "dbatoolsci-group1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"

        $newGroup = Add-DbaRegServerGroup -SqlInstance $script:instance2 -Name $group
        $newServer = Add-DbaRegServer -SqlInstance $script:instance2 -ServerName $srvName -Name $regSrvName -Description $regSrvDesc

        $srvName2 = "dbatoolsci-server2"
        $group2 = "dbatoolsci-group2"
        $regSrvName2 = "dbatoolsci-server21"
        $regSrvDesc2 = "dbatoolsci-server321"

        $newGroup2 = Add-DbaRegServerGroup -SqlInstance $script:instance2 -Name $group2
        $newServer2 = Add-DbaRegServer -SqlInstance $script:instance2 -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2

        $regSrvName3 = "dbatoolsci-server3"
        $srvName3 = "dbatoolsci-server3"
        $regSrvDesc3 = "dbatoolsci-server3desc"

        $newServer3 = Add-DbaRegServer -SqlInstance $script:instance2 -ServerName $srvName3 -Name $regSrvName3 -Description $regSrvDesc3

        $random = Get-Random
        $newDirectory = "C:\temp-$random"
    }
    AfterEach {
        Get-DbaRegServer -SqlInstance $script:instance2 | Where-Object Name -Match dbatoolsci | Remove-DbaRegServer -Confirm:$false
        Get-DbaRegServerGroup -SqlInstance $script:instance2 | Where-Object Name -Match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
        $results, $results2, $results3 | Remove-Item -ErrorAction Ignore

        Remove-Item $newDirectory -ErrorAction Ignore -Recurse -Force
    }

    It "should create an xml file" {
        $results = $newServer | Export-DbaRegServer
        $results -is [System.IO.FileInfo] | Should -Be $true
        $results.Extension -eq '.xml' | Should -Be $true
    }

    It "should create a specific xml file when using Path" {
        $results2 = $newGroup2 | Export-DbaRegServer -Path C:\temp
        $results2 -is [System.IO.FileInfo] | Should -Be $true
        $results2.FullName | Should -match 'C\:\\temp'
        Get-Content -Path $results2 -Raw | Should -Match $group2
    }

    It "creates an importable xml file" {
        $results3 = $newServer3 | Export-DbaRegServer -Path C:\temp
        Get-DbaRegServer -SqlInstance $script:instance2 | Where-Object Name -Match dbatoolsci | Remove-DbaRegServer -Confirm:$false
        Get-DbaRegServerGroup -SqlInstance $script:instance2 | Where-Object Name -Match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
        $results4 = Import-DbaRegServer -SqlInstance $script:instance2 -Path $results3
        $newServer3.ServerName | Should -BeIn $results4.ServerName
        $newServer3.Description | Should -BeIn $results4.Description
    }

    It "Create an xml file using FilePath" {
        $outputFileName = "C:\temp\dbatoolsci-regsrvr-export-$random.xml"
        $results = Export-DbaRegServer -SqlInstance $script:instance2 -FilePath $outputFileName
        $results -is [System.IO.FileInfo] | Should -Be $true
        $results.FullName | Should -Be $outputFileName
    }

    It "Create a regsrvr file using the FilePath alias OutFile" {
        $outputFileName = "C:\temp\dbatoolsci-regsrvr-export-$random.regsrvr"
        $results = Export-DbaRegServer -SqlInstance $script:instance2 -OutFile $outputFileName
        $results -is [System.IO.FileInfo] | Should -Be $true
        $results.FullName | Should -Be $outputFileName
    }

    It "Try to create an invalid file using FilePath" {
        $outputFileName = "C:\temp\dbatoolsci-regsrvr-export-$random.txt"
        { Export-DbaRegServer -SqlInstance $script:instance2 -FilePath $outputFileName } | Should -Throw -ErrorId "ParameterArgumentValidationError,Export-DbaRegServer"
    }

    It "Create an xml file using the FilePath alias FileName in a directory that does not yet exist" {
        $outputFileName = "$newDirectory\dbatoolsci-regsrvr-export-$random.xml"
        $results = Export-DbaRegServer -SqlInstance $script:instance2 -FileName $outputFileName
        $results -is [System.IO.FileInfo] | Should -Be $true
        $results.FullName | Should -Be $outputFileName
    }

    It "Ensure the Overwrite param is working" {
        $outputFileName = "C:\temp\dbatoolsci-regsrvr-export-$random.xml"
        $results = Export-DbaRegServer -SqlInstance $script:instance2 -FilePath $outputFileName
        $results -is [System.IO.FileInfo] | Should -Be $true
        $results.FullName | Should -Be $outputFileName

        # test without -Overwrite
        { Export-DbaRegServer -SqlInstance $script:instance2 -FilePath $outputFileName } | Should -Throw -ErrorId "RuntimeException"

        # test with -Overwrite
        $resultsOverwrite = Export-DbaRegServer -SqlInstance $script:instance2 -FilePath $outputFileName -Overwrite
        $resultsOverwrite -is [System.IO.FileInfo] | Should -Be $true
        $resultsOverwrite.FullName | Should -Be $outputFileName
    }

    It "Test with the Group param" {
        $outputFileName = "C:\temp\dbatoolsci-regsrvr-export-$random.xml"
        $results = Export-DbaRegServer -SqlInstance $script:instance2 -FilePath $outputFileName -Group $group
        $results -is [System.IO.FileInfo] | Should -Be $true
        $results.FullName | Should -Be $outputFileName

        $fileText = Get-Content -Path $results -Raw

        $fileText | Should -Match $group
        $fileText | Should -Not -Match $group2
    }

    It "Test with the Group param and multiple group names" {
        $outputFileName = "C:\temp\dbatoolsci-regsrvr-export-$random.xml"
        $results = Export-DbaRegServer -SqlInstance $script:instance2 -FilePath $outputFileName -Group @($group, $group2)
        $results.length | Should -Be 2

        $fileText = Get-Content -Path $results[0] -Raw

        $fileText | Should -Match $group
        $fileText | Should -Not -Match $group2

        $fileText = Get-Content -Path $results[1] -Raw

        $fileText | Should -Not -Match $group
        $fileText | Should -Match $group2
    }

    It "Test with the ExcludeGroup param" {
        $results = Export-DbaRegServer -SqlInstance $script:instance2 -ExcludeGroup $group2
        $results -is [System.IO.FileInfo] | Should -Be $true

        $fileText = Get-Content -Path $results -Raw

        $fileText | Should -Match $group
        $fileText | Should -Not -Match $group2
    }
}