param($ModuleName = 'dbatools')

Describe "Test-DbaPath" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $trueTest = (Get-DbaDbFile -SqlInstance $global:instance2 -Database master)[0].PhysicalName
        if ($trueTest.Length -eq 0) {
            Set-ItResult -Inconclusive -Because "Setup failed"
        }
        $falseTest = 'B:\FloppyDiskAreAwesome'
        $trueTestPath = [System.IO.Path]::GetDirectoryName($trueTest)
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaPath
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Path",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works" {
        It "Should return true if the path IS accessible to the instance" {
            $result = Test-DbaPath -SqlInstance $global:instance2 -Path $trueTest
            $result | Should -BeTrue
        }

        It "Should return false if the path IS NOT accessible to the instance" {
            $result = Test-DbaPath -SqlInstance $global:instance2 -Path $falseTest
            $result | Should -BeFalse
        }

        It "Should return multiple results when passed multiple paths" {
            $results = Test-DbaPath -SqlInstance $global:instance2 -Path $trueTest, $falseTest
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -BeTrue
            ($results | Where-Object FilePath -eq $falseTest).FileExists | Should -BeFalse
        }

        It "Should return multiple results when passed multiple instances" {
            $results = Test-DbaPath -SqlInstance $global:instance2, $global:instance1 -Path $falseTest
            foreach ($result in $results) {
                $result.FileExists | Should -BeFalse
            }
            ($results.SqlInstance | Sort-Object -Unique).Count | Should -Be 2
        }

        It "Should return pscustomobject results when passed an array (even with one path)" {
            $results = Test-DbaPath -SqlInstance $global:instance2 -Path @($trueTest)
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -BeTrue
        }

        It "Should return pscustomobject results indicating if the path is a file or a directory" {
            $results = Test-DbaPath -SqlInstance $global:instance2 -Path @($trueTest, $trueTestPath)
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -BeTrue
            ($results | Where-Object FilePath -eq $trueTestPath).FileExists | Should -BeTrue
            ($results | Where-Object FilePath -eq $trueTest).IsContainer | Should -BeFalse
            ($results | Where-Object FilePath -eq $trueTestPath).IsContainer | Should -BeTrue
        }
    }
}
