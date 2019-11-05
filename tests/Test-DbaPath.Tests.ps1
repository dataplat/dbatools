<#
    The below statement stays in for every test you build.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

<#
    Unit test is required for any command added
#>
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $trueTest = (Get-DbaDbFile -SqlInstance $script:instance2 -Database master)[0].PhysicalName
        if ($trueTest.Length -eq 0) {
            It "has failed setup" {
                Set-TestInconclusive -message "Setup failed"
            }
        }
        $falseTest = 'B:\FloppyDiskAreAwesome'
        $trueTestPath = [System.IO.Path]::GetDirectoryName($trueTest)
    }
    Context "Command actually works" {
        $result = Test-DbaPath -SqlInstance $script:instance2 -Path $trueTest
        It "Should only return true if the path IS accessible to the instance" {
            $result | Should Be $true
        }

        $result = Test-DbaPath -SqlInstance $script:instance2 -Path $falseTest
        It "Should only return false if the path IS NOT accessible to the instance" {
            $result | Should Be $false
        }
        $results = Test-DbaPath -SqlInstance $script:instance2 -Path $trueTest, $falseTest
        It "Should return multiple results when passed multiple paths" {
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should Be $true
            ($results | Where-Object FilePath -eq $falseTest).FileExists | Should Be $false
        }
        $results = Test-DbaPath -SqlInstance $script:instance2, $script:instance1 -Path $falseTest
        It "Should return multiple results when passed multiple instances" {
            foreach ($result in $results) {
                $result.FileExists | Should Be $false
            }
            ($results.SqlInstance | Sort-Object -Unique).Count | Should Be 2
        }
        $results = Test-DbaPath -SqlInstance $script:instance2 -Path @($trueTest)
        It "Should return pscustomobject results when passed an array (even with one path)" {
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should Be $true
        }
        $results = Test-DbaPath -SqlInstance $script:instance2 -Path @($trueTest, $trueTestPath)
        It "Should return pscustomobject results indicating if the path is a file or a directory" {
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should Be $true
            ($results | Where-Object FilePath -eq $trueTestPath).FileExists | Should Be $true
            ($results | Where-Object FilePath -eq $trueTest).IsContainer | Should Be $false
            ($results | Where-Object FilePath -eq $trueTestPath).IsContainer | Should Be $true
        }
    }
}