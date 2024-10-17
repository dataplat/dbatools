param($ModuleName = 'dbatools')

Describe "Test-DbaPath" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $trueTest = (Get-DbaDbFile -SqlInstance $env:instance2 -Database master)[0].PhysicalName
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
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type Object
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command actually works" {
        It "Should return true if the path IS accessible to the instance" {
            $result = Test-DbaPath -SqlInstance $env:instance2 -Path $trueTest
            $result | Should -BeTrue
        }

        It "Should return false if the path IS NOT accessible to the instance" {
            $result = Test-DbaPath -SqlInstance $env:instance2 -Path $falseTest
            $result | Should -BeFalse
        }

        It "Should return multiple results when passed multiple paths" {
            $results = Test-DbaPath -SqlInstance $env:instance2 -Path $trueTest, $falseTest
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -BeTrue
            ($results | Where-Object FilePath -eq $falseTest).FileExists | Should -BeFalse
        }

        It "Should return multiple results when passed multiple instances" {
            $results = Test-DbaPath -SqlInstance $env:instance2, $env:instance1 -Path $falseTest
            foreach ($result in $results) {
                $result.FileExists | Should -BeFalse
            }
            ($results.SqlInstance | Sort-Object -Unique).Count | Should -Be 2
        }

        It "Should return pscustomobject results when passed an array (even with one path)" {
            $results = Test-DbaPath -SqlInstance $env:instance2 -Path @($trueTest)
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -BeTrue
        }

        It "Should return pscustomobject results indicating if the path is a file or a directory" {
            $results = Test-DbaPath -SqlInstance $env:instance2 -Path @($trueTest, $trueTestPath)
            ($results | Where-Object FilePath -eq $trueTest).FileExists | Should -BeTrue
            ($results | Where-Object FilePath -eq $trueTestPath).FileExists | Should -BeTrue
            ($results | Where-Object FilePath -eq $trueTest).IsContainer | Should -BeFalse
            ($results | Where-Object FilePath -eq $trueTestPath).IsContainer | Should -BeTrue
        }
    }
}
