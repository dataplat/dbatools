#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaRegServer",
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
                "Path",
                "InputObject",
                "Group",
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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the temp files that we want to clean up after the test, we create a directory that we can delete at the end.
        $tempPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $tempPath -ItemType Directory
        $global:tempFilesToRemove = @()

        # Set variables for test objects
        $global:srvName = "dbatoolsci-server1"
        $global:group = "dbatoolsci-group1"
        $global:regSrvName = "dbatoolsci-server12"
        $global:regSrvDesc = "dbatoolsci-server123"

        $global:srvName2 = "dbatoolsci-server2"
        $global:group2 = "dbatoolsci-group1a"
        $global:regSrvName2 = "dbatoolsci-server21"
        $global:regSrvDesc2 = "dbatoolsci-server321"

        $global:regSrvName3 = "dbatoolsci-server3"
        $global:srvName3 = "dbatoolsci-server3"
        $global:regSrvDesc3 = "dbatoolsci-server3desc"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    BeforeEach {
        # We want to run all commands in the BeforeEach block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Create test objects for each test
        $global:newGroup = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance2 -Name $global:group
        $global:newServer = Add-DbaRegServer -SqlInstance $TestConfig.instance2 -ServerName $global:srvName -Name $global:regSrvName -Description $global:regSrvDesc -Group $global:newGroup.Name

        $global:newGroup2 = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance2 -Name $global:group2
        $global:newServer2 = Add-DbaRegServer -SqlInstance $TestConfig.instance2 -ServerName $global:srvName2 -Name $global:regSrvName2 -Description $global:regSrvDesc2

        $global:newServer3 = Add-DbaRegServer -SqlInstance $TestConfig.instance2 -ServerName $global:srvName3 -Name $global:regSrvName3 -Description $global:regSrvDesc3

        # We want to run all commands outside of the BeforeEach block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterEach {
        # Clean up test objects
        Get-DbaRegServer -SqlInstance $TestConfig.instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false -ErrorAction SilentlyContinue
        Get-DbaRegServerGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -Path $global:tempFilesToRemove -ErrorAction SilentlyContinue
        $global:tempFilesToRemove = @()
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up any remaining test objects
        Get-DbaRegServer -SqlInstance $TestConfig.instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false -ErrorAction SilentlyContinue
        Get-DbaRegServerGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false -ErrorAction SilentlyContinue

        # Remove the temp directory
        Remove-Item -Path $tempPath -Recurse -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When importing registered server objects" {
        It "imports group objects" {
            $results = $global:newServer.Parent | Import-DbaRegServer -SqlInstance $TestConfig.instance2
            $results.Description | Should -Be $global:regSrvDesc
            $results.ServerName | Should -Be $global:srvName
            $results.Parent.Name | Should -Be $global:group
        }

        It "imports registered server objects" {
            $results = $global:newServer2 | Import-DbaRegServer -SqlInstance $TestConfig.instance2
            $results.ServerName | Should -Be $global:newServer2.ServerName
            $results.Parent.Name | Should -Be $global:newServer2.Parent.Name
        }

        It "imports a file from Export-DbaRegServer" {
            $exportPath = $global:newServer3 | Export-DbaRegServer -Path $tempPath
            $global:tempFilesToRemove += $exportPath.FullName
            $results = Import-DbaRegServer -SqlInstance $TestConfig.instance2 -Path $exportPath
            $results.ServerName | Should -Be @("dbatoolsci-server3")
            $results.Description | Should -Be @("dbatoolsci-server3desc")
        }

        It "imports from a random object so long as it has ServerName" {
            $object = [pscustomobject]@{
                ServerName = "dbatoolsci-randobject"
            }
            $results = $object | Import-DbaRegServer -SqlInstance $TestConfig.instance2
            $results.ServerName | Should -Be "dbatoolsci-randobject"
            $results.Name | Should -Be "dbatoolsci-randobject"
        }

        It "does not import object if ServerName does not exist" {
            $object = [pscustomobject]@{
                Name = "dbatoolsci-randobject"
            }
            $results = $object | Import-DbaRegServer -SqlInstance $TestConfig.instance2 -WarningAction SilentlyContinue -WarningVariable warn
            $results | Should -Be $null
            $warn | Should -Match "No servers added"
        }
    }
}
